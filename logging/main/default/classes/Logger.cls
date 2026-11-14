/**
 * The one logging API application code calls.
 *
 * Entries are buffered and published as Log_Event__e platform events, which
 * are published immediately, so a log is kept even when the transaction that
 * wrote it rolls back. LogEventTrigger turns the events into Log__c rows and
 * raises Slack alerts.
 *
 * Handled exception:   Logger.error('MyClass.myMethod', e);  then Logger.flush();
 * Entry-point guard:   catch (Exception e) { Logger.unhandled('MyClass', e); throw e; }
 *
 * Logger never throws: a failure to log must not break the caller.
 */
public without sharing class Logger {
  public static final String LEVEL_ERROR = 'ERROR';
  public static final String LEVEL_WARN = 'WARN';

  public static final String SOURCE_APEX = 'Apex';
  public static final String SOURCE_FLOW = 'Flow';
  public static final String SOURCE_BATCH = 'Batch';
  public static final String SOURCE_QUEUEABLE = 'Queueable';
  public static final String SOURCE_SCHEDULABLE = 'Schedulable';
  public static final String SOURCE_FUTURE = 'Future';
  public static final String SOURCE_INTEGRATION = 'Integration';
  public static final String SOURCE_EMAIL = 'Email';
  public static final String SOURCE_LOGGING = 'Logging';

  private static final Integer MAX_LONG_TEXT = 32000;
  private static final Integer MAX_TEXT = 255;
  private static final Integer MAX_BUFFER = 200;
  private static final Integer MAX_RESPONSE_EXCERPT = 2000;
  private static final Integer MAX_CAUSES = 5;

  @TestVisible
  private static List<Log_Event__e> buffer = new List<Log_Event__e>();
  private static String currentFeature;

  /** A log entry. Use the convenience methods below where they fit. */
  public class Entry {
    public String level = LEVEL_ERROR;
    public String sourceType = SOURCE_APEX;
    public String sourceName;
    public String message;
    public String exceptionType;
    public String stackTrace;
    public String recordId;
    public String details;
    public String feature;
    public Boolean isHandled = true;
  }

  /** Tags every later entry in this transaction with a feature name. */
  public static void setFeature(String feature) {
    currentFeature = feature;
  }

  /** A caught exception that the code dealt with. Buffered until flush(). */
  public static void error(String source, Exception e) {
    error(source, e, null);
  }

  public static void error(String source, Exception e, Id recordId) {
    Entry entry = entryFor(SOURCE_APEX, source, e);
    entry.recordId = recordId;
    add(entry);
  }

  public static void error(String source, String message) {
    Entry entry = new Entry();
    entry.sourceName = source;
    entry.message = message;
    add(entry);
  }

  public static void warn(String source, String message) {
    Entry entry = new Entry();
    entry.level = LEVEL_WARN;
    entry.sourceName = source;
    entry.message = message;
    add(entry);
  }

  /**
   * An exception that is about to escape an Apex entry point. Publishes at
   * once, because the caller rethrows straight afterwards.
   */
  public static void unhandled(String source, Exception e) {
    unhandled(SOURCE_APEX, source, e);
  }

  /** As above, for async jobs: pass SOURCE_QUEUEABLE, SOURCE_BATCH and so on. */
  public static void unhandled(String sourceType, String source, Exception e) {
    Entry entry = entryFor(sourceType, source, e);
    entry.isHandled = false;
    add(entry);
    flush();
  }

  /** A callout that returned a failure response. Publishes at once. */
  public static void integrationError(
    String source,
    HttpRequest request,
    HttpResponse response
  ) {
    Entry entry = new Entry();
    entry.sourceType = SOURCE_INTEGRATION;
    entry.sourceName = source;
    if (response != null) {
      entry.message =
        'HTTP ' +
        response.getStatusCode() +
        ' ' +
        (response.getStatus() == null ? '' : response.getStatus());
      String body = response.getBody();
      entry.details =
        describe(request) +
        '\nResponse: ' +
        (body == null ? '' : body.left(MAX_RESPONSE_EXCERPT));
    } else {
      entry.message = 'No response';
      entry.details = describe(request);
    }
    add(entry);
    flush();
  }

  /** A callout that threw, such as a timeout. Publishes at once. */
  public static void integrationError(
    String source,
    HttpRequest request,
    Exception e
  ) {
    Entry entry = entryFor(SOURCE_INTEGRATION, source, e);
    entry.details = describe(request);
    add(entry);
    flush();
  }

  /** Buffers any entry. Used by the capture points (flow, batch, email). */
  public static void add(Entry entry) {
    try {
      if (entry == null || !LogSettings.isEnabled()) {
        return;
      }
      buffer.add(toEvent(entry));
      if (buffer.size() >= MAX_BUFFER) {
        flush();
      }
    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, 'Logger.add failed: ' + e.getMessage());
    }
  }

  /** Publishes everything buffered so far. Safe to call with nothing buffered. */
  public static void flush() {
    if (buffer.isEmpty()) {
      return;
    }
    List<Log_Event__e> pending = buffer;
    buffer = new List<Log_Event__e>();
    try {
      // System mode: a user with no access to the event must still be able to log.
      for (
        Database.SaveResult result : EventBus.publishWithAccessLevel(
          pending,
          AccessLevel.SYSTEM_MODE
        )
      ) {
        if (!result.isSuccess()) {
          System.debug(
            LoggingLevel.ERROR,
            'Logger could not publish: ' + result.getErrors()
          );
        }
      }
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Logger.flush failed: ' + e.getMessage()
      );
    }
  }

  /** Builds an entry from an exception, for callers that add more context. */
  public static Entry entryFor(String sourceType, String source, Exception e) {
    Entry entry = new Entry();
    entry.sourceType = sourceType;
    entry.sourceName = source;
    if (e != null) {
      entry.message = e.getMessage();
      entry.exceptionType = e.getTypeName();
      entry.stackTrace = stackTraceOf(e);
    }
    return entry;
  }

  private static String stackTraceOf(Exception e) {
    String trace = e.getStackTraceString();
    Exception cause = e.getCause();
    Integer depth = 0;
    while (cause != null && depth < MAX_CAUSES) {
      trace +=
        '\nCaused by: ' +
        cause.getTypeName() +
        ': ' +
        cause.getMessage() +
        '\n' +
        cause.getStackTraceString();
      cause = cause.getCause();
      depth++;
    }
    return trace;
  }

  /** Method and endpoint only. Query strings, headers and bodies can hold secrets. */
  private static String describe(HttpRequest request) {
    if (request == null) {
      return 'Request: unknown';
    }
    String endpoint = request.getEndpoint();
    return 'Request: ' +
      request.getMethod() +
      ' ' +
      (endpoint == null ? '' : endpoint.substringBefore('?'));
  }

  private static Log_Event__e toEvent(Entry entry) {
    Request current = Request.getCurrent();
    return new Log_Event__e(
      Level__c = entry.level,
      Source_Type__c = shorten(entry.sourceType, 40),
      Source_Name__c = shorten(entry.sourceName, MAX_TEXT),
      Message__c = shorten(entry.message, MAX_LONG_TEXT),
      Exception_Type__c = shorten(entry.exceptionType, MAX_TEXT),
      Stack_Trace__c = shorten(entry.stackTrace, MAX_LONG_TEXT),
      Record_Id__c = shorten(entry.recordId, 18),
      Details__c = shorten(entry.details, MAX_LONG_TEXT),
      Feature__c = shorten(
        entry.feature == null ? currentFeature : entry.feature,
        80
      ),
      Is_Handled__c = entry.isHandled != false,
      Request_Id__c = shorten(current.getRequestId(), MAX_TEXT),
      Quiddity__c = shorten(String.valueOf(current.getQuiddity()), 60),
      User_Id__c = UserInfo.getUserId(),
      Occurred_At__c = System.now()
    );
  }

  private static String shorten(String value, Integer max) {
    return value == null ? null : value.left(max);
  }
}
