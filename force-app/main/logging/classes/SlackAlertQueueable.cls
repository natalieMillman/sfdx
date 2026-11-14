/**
 * Sends the real-time Slack alerts chosen by LogEventHandler and records the
 * outcome on each Log__c. Deliberately has no finalizer and logs nothing
 * through Logger: a failed alert must not raise another alert.
 */
public without sharing class SlackAlertQueueable implements Queueable, Database.AllowsCallouts {
  public class Alert {
    public Id logId;
    public String channel;
    public Integer occurrences;

    public Alert(Id logId, String channel, Integer occurrences) {
      this.logId = logId;
      this.channel = channel;
      this.occurrences = occurrences;
    }
  }

  private final List<Alert> alerts;
  private final Integer overflow;

  public SlackAlertQueueable(List<Alert> alerts, Integer overflow) {
    this.alerts = alerts;
    this.overflow = overflow;
  }

  public void execute(QueueableContext context) {
    try {
      send();
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Slack alerts failed: ' +
          e.getMessage() +
          '\n' +
          e.getStackTraceString()
      );
    }
  }

  private void send() {
    Set<Id> logIds = new Set<Id>();
    for (Alert alert : alerts) {
      logIds.add(alert.logId);
    }
    Map<Id, Log__c> logs = new Map<Id, Log__c>(
      [
        SELECT
          Id,
          Name,
          Source_Type__c,
          Source_Name__c,
          Exception_Type__c,
          Summary__c,
          Feature__c,
          Is_Handled__c,
          Occurred_At__c,
          User__r.Name
        FROM Log__c
        WHERE Id IN :logIds
        WITH SYSTEM_MODE
      ]
    );

    // All callouts first, then one update: DML before a callout is not allowed.
    List<Log__c> outcomes = new List<Log__c>();
    for (Alert alert : alerts) {
      Log__c log = logs.get(alert.logId);
      if (log == null) {
        continue;
      }
      SlackClient.Result result = SlackClient.post(
        alert.channel,
        LogSlackFormatter.alert(log, alert.occurrences)
      );
      outcomes.add(
        new Log__c(
          Id = log.Id,
          Alert_Status__c = result.ok ? 'Sent' : 'Failed',
          Alerted_At__c = result.ok ? System.now() : null,
          Alert_Error__c = result.ok || result.error == null
            ? null
            : result.error.left(255)
        )
      );
    }
    if (overflow != null && overflow > 0) {
      SlackClient.post(
        LogSettings.defaultAlertChannel(),
        LogSlackFormatter.overflow(overflow)
      );
    }
    Database.update(outcomes, false, AccessLevel.SYSTEM_MODE);
  }
}
