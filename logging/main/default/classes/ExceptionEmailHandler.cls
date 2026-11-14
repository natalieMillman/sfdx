/**
 * Email service handler that turns Salesforce's own error emails into log
 * entries: Apex unhandled exception emails and Flow error emails.
 *
 * This is the backstop for failures nothing else caught (Apex with no
 * entry-point guard, flows with no fault path). It is best effort: the email
 * wording is not a published contract and Salesforce does not send an email
 * for every repeat of the same error. Anything it cannot recognise is still
 * logged, with source type Email, so nothing is silently dropped.
 */
public without sharing class ExceptionEmailHandler implements Messaging.InboundEmailHandler {
  private static final Integer DUPLICATE_WINDOW_MINUTES = 5;
  private static final Integer MATCH_PREFIX_LENGTH = 80;
  private static final String EMAIL_QUIDDITY = 'INBOUND_EMAIL_SERVICE';

  public Messaging.InboundEmailResult handleInboundEmail(
    Messaging.InboundEmail email,
    Messaging.InboundEnvelope envelope
  ) {
    Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
    result.success = true;
    try {
      String body = String.isNotBlank(email.plainTextBody)
        ? email.plainTextBody
        : (email.htmlBody == null ? '' : email.htmlBody.stripHtmlTags());
      Logger.Entry entry = parse(email.subject, body);
      if (!alreadyLogged(entry)) {
        Logger.add(entry);
        Logger.flush();
      }
    } catch (Exception e) {
      Logger.Entry failure = Logger.entryFor(
        Logger.SOURCE_LOGGING,
        'ExceptionEmailHandler',
        e
      );
      Logger.add(failure);
      Logger.flush();
    }
    return result;
  }

  @TestVisible
  private static Logger.Entry parse(String subject, String body) {
    String safeSubject = subject == null ? '' : subject;
    String safeBody = body == null ? '' : body;
    Logger.Entry entry;
    if (
      safeBody.containsIgnoreCase('Flow API Name') ||
      safeBody.containsIgnoreCase('Flow Interview') ||
      safeSubject.containsIgnoreCase('During Flow')
    ) {
      entry = parseFlow(safeSubject, safeBody);
    } else if (
      safeBody.containsIgnoreCase('Apex script unhandled') ||
      safeSubject.containsIgnoreCase('script exception')
    ) {
      entry = parseApex(safeSubject, safeBody);
    } else {
      entry = new Logger.Entry();
      entry.sourceType = Logger.SOURCE_EMAIL;
      entry.sourceName = String.isBlank(safeSubject)
        ? 'Unrecognised error email'
        : safeSubject;
      entry.message = safeSubject;
    }
    entry.isHandled = false;
    entry.details = 'Captured from an error email.\n' + safeBody;
    return entry;
  }

  private static Logger.Entry parseApex(String subject, String body) {
    Logger.Entry entry = new Logger.Entry();
    entry.sourceType = Logger.SOURCE_APEX;

    String batchClass = firstGroup(
      body,
      'Failed to process batch for class \'([\\w.]+)\''
    );
    String queueableClass = firstGroup(
      body,
      'Failed to process Queueable job for class ([\\w.]+)'
    );
    if (batchClass != null) {
      entry.sourceType = Logger.SOURCE_BATCH;
      entry.sourceName = batchClass;
    } else if (queueableClass != null) {
      entry.sourceType = Logger.SOURCE_QUEUEABLE;
      entry.sourceName = queueableClass;
    } else {
      // Subject: "Developer script exception from <org> : <class> : <message>"
      List<String> parts = subject.split(' : ');
      String fromStack = firstGroup(
        body,
        '(?m)^(?:Class|Trigger)\\.([\\w]+)[\\w.]*: line \\d+'
      );
      entry.sourceName = parts.size() >= 2 && String.isNotBlank(parts[1])
        ? parts[1].trim()
        : (fromStack == null ? 'Unknown Apex' : fromStack);
    }

    entry.exceptionType = firstGroup(
      body,
      '(?:caused by: )?((?:[A-Za-z_]\\w*\\.)*[A-Za-z_]\\w*Exception):'
    );
    String message = entry.exceptionType == null
      ? null
      : firstGroup(
          body,
          Pattern.quote(entry.exceptionType) + ':\\s*([^\\r\\n]+)'
        );
    entry.message = message != null
      ? message.trim()
      : (subject.contains(' : ') ? subject.substringAfterLast(' : ') : subject);

    List<String> stack = new List<String>();
    Matcher lines = Pattern.compile(
        '(?m)^((?:Class|Trigger|AnonymousBlock|External entry point)[^\\r\\n]*)'
      )
      .matcher(body);
    while (lines.find()) {
      stack.add(lines.group(1).trim());
    }
    entry.stackTrace = stack.isEmpty() ? null : String.join(stack, '\n');
    return entry;
  }

  private static Logger.Entry parseFlow(String subject, String body) {
    Logger.Entry entry = new Logger.Entry();
    entry.sourceType = Logger.SOURCE_FLOW;
    entry.exceptionType = 'FlowFault';

    String apiName = firstGroup(body, 'Flow API Name:\\s*([\\w]+)');
    if (apiName == null) {
      apiName = firstGroup(subject, 'Flow "([^"]+)"');
    }
    entry.sourceName = apiName == null ? 'Unknown flow' : apiName;

    String message = firstGroup(body, 'Error Occurred:\\s*([^\\r\\n]+)');
    if (message == null && subject.contains('": ')) {
      message = subject.substringAfter('": ');
    }
    entry.message = String.isBlank(message) ? subject : message.trim();
    return entry;
  }

  /**
   * True when an entry-point guard, finalizer or batch event already logged
   * this failure in the last few minutes, so the email would count it twice.
   */
  private static Boolean alreadyLogged(Logger.Entry entry) {
    if (
      entry.sourceType == Logger.SOURCE_EMAIL ||
      String.isBlank(entry.exceptionType) ||
      String.isBlank(entry.message)
    ) {
      return false;
    }
    Datetime since = System.now().addMinutes(-DUPLICATE_WINDOW_MINUTES);
    String prefix = entry.message.replaceAll('\\s+', ' ')
      .left(MATCH_PREFIX_LENGTH);
    for (Log__c recent : [
      SELECT Summary__c
      FROM Log__c
      WHERE
        Is_Handled__c = FALSE
        AND Exception_Type__c = :entry.exceptionType
        AND Quiddity__c != :EMAIL_QUIDDITY
        AND CreatedDate >= :since
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
      LIMIT 200
    ]) {
      if (recent.Summary__c != null && recent.Summary__c.startsWith(prefix)) {
        return true;
      }
    }
    return false;
  }

  private static String firstGroup(String text, String regex) {
    Matcher matcher = Pattern.compile(regex).matcher(text);
    return matcher.find() ? matcher.group(1) : null;
  }
}
