/**
 * Turns Log_Event__e platform events into Log__c rows, then decides which of
 * them raise a real-time Slack alert.
 *
 * Runs in the platform event trigger, outside the transaction that logged,
 * so nothing here can roll back or break application code.
 */
public without sharing class LogEventHandler {
  @TestVisible
  private static final Integer MAX_RETRIES = 3;
  private static final Integer MAX_LONG_TEXT = 32000;
  private static final Integer FINGERPRINT_MESSAGE_LENGTH = 500;
  private static final Integer MAX_ALERTS_HARD_LIMIT = 50;

  private static final String STATUS_NONE = 'None';
  private static final String STATUS_PENDING = 'Pending';
  private static final String STATUS_SENT = 'Sent';
  private static final String STATUS_SUPPRESSED = 'Suppressed';
  private static final String STATUS_FAILED = 'Failed';

  @TestVisible
  private static Boolean failPersist = false;
  @TestVisible
  private static Boolean failDispatch = false;

  public static void handle(List<Log_Event__e> events) {
    List<Log__c> logs;
    try {
      logs = persist(events);
    } catch (Exception e) {
      // Ask the event bus to redeliver a few times (row locks and similar
      // clear on their own), then give up rather than loop forever.
      if (EventBus.TriggerContext.currentContext().retries < MAX_RETRIES) {
        throw new EventBus.RetryableException(
          'Could not save logs: ' + e.getMessage()
        );
      }
      System.debug(
        LoggingLevel.ERROR,
        'Logging gave up after retries: ' + e.getMessage()
      );
      return;
    }

    // The logs are saved. An alerting failure must not redeliver the events,
    // which would save them twice.
    try {
      dispatchAlerts(logs);
    } catch (Exception e) {
      recordOwnFailure('LogEventHandler.dispatchAlerts', e);
    }
  }

  private static List<Log__c> persist(List<Log_Event__e> events) {
    if (failPersist) {
      throw new HandlerException('Simulated failure');
    }
    List<Log__c> logs = new List<Log__c>();
    for (Log_Event__e event : events) {
      logs.add(toLog(event));
    }
    List<Log__c> saved = new List<Log__c>();
    List<Database.SaveResult> results = Database.insert(
      logs,
      false,
      AccessLevel.SYSTEM_MODE
    );
    for (Integer i = 0; i < results.size(); i++) {
      if (results[i].isSuccess()) {
        saved.add(logs[i]);
      } else {
        System.debug(
          LoggingLevel.ERROR,
          'Could not save log: ' + results[i].getErrors()
        );
      }
    }
    if (saved.isEmpty() && !logs.isEmpty()) {
      throw new HandlerException('No log in the batch could be saved');
    }
    return saved;
  }

  /**
   * One alert per distinct failure in the batch. Repeats of a failure that
   * alerted recently, and anything over the per-batch cap, are suppressed.
   */
  private static void dispatchAlerts(List<Log__c> logs) {
    if (failDispatch) {
      throw new HandlerException('Simulated alert failure');
    }
    Map<String, AlertGroup> groups = new Map<String, AlertGroup>();
    List<AlertGroup> ordered = new List<AlertGroup>();
    for (Log__c log : logs) {
      Log_Alert_Rule__mdt rule = LogAlertRules.match(log);
      if (rule == null) {
        continue;
      }
      AlertGroup existing = groups.get(log.Fingerprint__c);
      if (existing == null) {
        AlertGroup created = new AlertGroup(log, rule);
        groups.put(log.Fingerprint__c, created);
        ordered.add(created);
      } else {
        existing.repeats.add(log);
      }
    }
    if (ordered.isEmpty()) {
      return;
    }

    Set<String> throttled = recentlyAlerted(groups, logs);
    Integer maxAlerts = Math.min(
      LogSettings.maxAlertsPerBatch(),
      MAX_ALERTS_HARD_LIMIT
    );
    List<SlackAlertQueueable.Alert> alerts = new List<SlackAlertQueueable.Alert>();
    List<Log__c> outcomes = new List<Log__c>();
    Integer overflow = 0;

    for (AlertGroup alertGroup : ordered) {
      for (Log__c repeat : alertGroup.repeats) {
        outcomes.add(
          outcome(repeat, STATUS_SUPPRESSED, alertGroup.channel, null)
        );
      }
      Log__c first = alertGroup.first;
      if (String.isBlank(alertGroup.channel)) {
        outcomes.add(
          outcome(first, STATUS_FAILED, null, 'No Slack channel configured')
        );
      } else if (throttled.contains(first.Fingerprint__c)) {
        outcomes.add(
          outcome(first, STATUS_SUPPRESSED, alertGroup.channel, null)
        );
      } else if (alerts.size() >= maxAlerts) {
        overflow += 1 + alertGroup.repeats.size();
        outcomes.add(
          outcome(first, STATUS_SUPPRESSED, alertGroup.channel, null)
        );
      } else {
        alerts.add(
          new SlackAlertQueueable.Alert(
            first.Id,
            alertGroup.channel,
            1 + alertGroup.repeats.size()
          )
        );
        outcomes.add(outcome(first, STATUS_PENDING, alertGroup.channel, null));
      }
    }

    Database.update(outcomes, false, AccessLevel.SYSTEM_MODE);
    if (!alerts.isEmpty()) {
      System.enqueueJob(new SlackAlertQueueable(alerts, overflow));
    }
  }

  /** Fingerprints that already alerted within their rule's throttle window. */
  private static Set<String> recentlyAlerted(
    Map<String, AlertGroup> groups,
    List<Log__c> currentBatch
  ) {
    Set<String> throttled = new Set<String>();
    Integer longestWindow = 0;
    for (AlertGroup alertGroup : groups.values()) {
      longestWindow = Math.max(longestWindow, alertGroup.throttleMinutes);
    }
    if (longestWindow == 0) {
      return throttled;
    }
    Datetime now = System.now();
    Datetime since = now.addMinutes(-longestWindow);
    for (Log__c prior : [
      SELECT Fingerprint__c, CreatedDate
      FROM Log__c
      WHERE
        Fingerprint__c IN :groups.keySet()
        AND Alert_Status__c IN (:STATUS_SENT, :STATUS_PENDING)
        AND CreatedDate >= :since
        AND Id NOT IN :currentBatch
      WITH SYSTEM_MODE
      ORDER BY CreatedDate DESC
      LIMIT 2000
    ]) {
      AlertGroup alertGroup = groups.get(prior.Fingerprint__c);
      if (
        alertGroup != null &&
        prior.CreatedDate >= now.addMinutes(-alertGroup.throttleMinutes)
      ) {
        throttled.add(prior.Fingerprint__c);
      }
    }
    return throttled;
  }

  private static Log__c outcome(
    Log__c log,
    String status,
    String channel,
    String error
  ) {
    return new Log__c(
      Id = log.Id,
      Alert_Status__c = status,
      Alert_Channel__c = channel == null ? null : channel.left(80),
      Alert_Error__c = error
    );
  }

  /**
   * Saves a row about a failure in the logging pipeline itself. Its source
   * type is Logging, which never matches an alert rule.
   */
  private static void recordOwnFailure(String source, Exception e) {
    try {
      Database.insert(
        new Log__c(
          Level__c = Logger.LEVEL_ERROR,
          Source_Type__c = Logger.SOURCE_LOGGING,
          Source_Name__c = source,
          Message__c = e.getMessage(),
          Summary__c = e.getMessage() == null ? null : e.getMessage().left(255),
          Exception_Type__c = e.getTypeName(),
          Stack_Trace__c = e.getStackTraceString(),
          Is_Handled__c = true,
          Occurred_At__c = System.now(),
          Alert_Status__c = STATUS_NONE
        ),
        false,
        AccessLevel.SYSTEM_MODE
      );
    } catch (Exception ignored) {
      System.debug(LoggingLevel.ERROR, source + ' failed: ' + e.getMessage());
    }
  }

  private static Log__c toLog(Log_Event__e event) {
    String message = event.Message__c;
    return new Log__c(
      Level__c = event.Level__c,
      Source_Type__c = event.Source_Type__c,
      Source_Name__c = event.Source_Name__c,
      Message__c = message == null ? null : message.left(MAX_LONG_TEXT),
      Summary__c = message == null
        ? null
        : message.replaceAll('\\s+', ' ').left(255),
      Exception_Type__c = event.Exception_Type__c,
      Stack_Trace__c = event.Stack_Trace__c,
      Record_Id__c = event.Record_Id__c,
      Details__c = event.Details__c,
      Feature__c = event.Feature__c,
      Is_Handled__c = event.Is_Handled__c,
      Request_Id__c = event.Request_Id__c,
      Quiddity__c = event.Quiddity__c,
      User__c = userIdOf(event.User_Id__c),
      Occurred_At__c = event.Occurred_At__c == null
        ? System.now()
        : event.Occurred_At__c,
      Fingerprint__c = fingerprintOf(event),
      Alert_Status__c = STATUS_NONE
    );
  }

  private static Id userIdOf(String value) {
    try {
      Id userId = Id.valueOf(value);
      return userId.getSobjectType() == User.SObjectType ? userId : null;
    } catch (Exception e) {
      return null;
    }
  }

  /**
   * The same failure gets the same fingerprint even when the message carries
   * a different record id or number each time.
   */
  @TestVisible
  private static String fingerprintOf(Log_Event__e event) {
    String message = event.Message__c == null ? '' : event.Message__c;
    message = message.left(FINGERPRINT_MESSAGE_LENGTH)
      .replaceAll(
        '\\b(?=[a-zA-Z0-9]*\\d)[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?\\b',
        '#'
      )
      .replaceAll('\\d+', '#');
    String key = String.join(
      new List<String>{
        String.valueOf(event.Source_Type__c),
        String.valueOf(event.Source_Name__c),
        String.valueOf(event.Exception_Type__c),
        message
      },
      '|'
    );
    return EncodingUtil.convertToHex(
      Crypto.generateDigest('SHA-256', Blob.valueOf(key))
    );
  }

  private class AlertGroup {
    final Log__c first;
    final List<Log__c> repeats = new List<Log__c>();
    final String channel;
    final Integer throttleMinutes;

    AlertGroup(Log__c first, Log_Alert_Rule__mdt rule) {
      this.first = first;
      this.channel = LogAlertRules.channelFor(rule);
      this.throttleMinutes = LogAlertRules.throttleMinutesFor(rule);
    }
  }

  private class HandlerException extends Exception {
  }
}
