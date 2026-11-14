/**
 * Posts one Slack message tabulating the last 24 hours of logged errors.
 *
 * Schedule it with scripts/apex/schedule-logging-jobs.apex. A scheduled job
 * cannot call out directly, so the scheduled run enqueues Sender, which does
 * the work. To post a summary on demand:
 *   System.enqueueJob(new LogDailySummaryJob.Sender());
 */
public without sharing class LogDailySummaryJob implements Schedulable {
  @TestVisible
  private static final Integer MAX_ROWS = 25;

  public void execute(SchedulableContext context) {
    System.enqueueJob(new Sender());
  }

  public class Sender implements Queueable, Database.AllowsCallouts {
    public void execute(QueueableContext context) {
      send(System.now());
    }
  }

  @TestVisible
  private static SlackClient.Result send(Datetime until) {
    SlackClient.Result result;
    try {
      Datetime since = until.addHours(-24);
      LogSlackFormatter.Totals totals = totalsSince(since);
      List<LogSlackFormatter.Row> rows = rowsSince(since, totals);
      result = SlackClient.post(
        LogSettings.dailySummaryChannel(),
        LogSlackFormatter.dailySummary(totals, rows, until)
      );
    } catch (Exception e) {
      result = new SlackClient.Result();
      result.error = e.getTypeName() + ': ' + e.getMessage();
    }
    if (!result.ok) {
      // Source type Logging never alerts, so this cannot loop. It shows up
      // in the Logs tab and in tomorrow's summary.
      Logger.Entry entry = new Logger.Entry();
      entry.sourceType = Logger.SOURCE_LOGGING;
      entry.sourceName = 'LogDailySummaryJob';
      entry.message = 'Daily summary was not delivered: ' + result.error;
      Logger.add(entry);
      Logger.flush();
    }
    return result;
  }

  private static LogSlackFormatter.Totals totalsSince(Datetime since) {
    LogSlackFormatter.Totals totals = new LogSlackFormatter.Totals();
    for (AggregateResult byLevel : [
      SELECT Level__c level, Is_Handled__c handled, COUNT(Id) total
      FROM Log__c
      WHERE Occurred_At__c >= :since
      WITH SYSTEM_MODE
      GROUP BY Level__c, Is_Handled__c
    ]) {
      Integer total = (Integer) byLevel.get('total');
      if ((String) byLevel.get('level') == Logger.LEVEL_ERROR) {
        totals.errors += total;
        if ((Boolean) byLevel.get('handled') == false) {
          totals.unhandled += total;
        }
      } else {
        totals.warnings += total;
      }
    }
    for (AggregateResult byStatus : [
      SELECT Alert_Status__c status, COUNT(Id) total
      FROM Log__c
      WHERE Occurred_At__c >= :since AND Alert_Status__c IN ('Sent', 'Failed')
      WITH SYSTEM_MODE
      GROUP BY Alert_Status__c
    ]) {
      Integer total = (Integer) byStatus.get('total');
      if ((String) byStatus.get('status') == 'Sent') {
        totals.alertsSent = total;
      } else {
        totals.alertsFailed = total;
      }
    }
    totals.distinctFailures = (Integer) [
        SELECT COUNT_DISTINCT(Fingerprint__c) total
        FROM Log__c
        WHERE Occurred_At__c >= :since AND Level__c = :Logger.LEVEL_ERROR
        WITH SYSTEM_MODE
      ][0]
      .get('total');
    return totals;
  }

  private static List<LogSlackFormatter.Row> rowsSince(
    Datetime since,
    LogSlackFormatter.Totals totals
  ) {
    List<LogSlackFormatter.Row> rows = new List<LogSlackFormatter.Row>();
    for (AggregateResult grouped : [
      SELECT
        Source_Type__c sourceType,
        Source_Name__c sourceName,
        Exception_Type__c exceptionType,
        Is_Handled__c handled,
        COUNT(Id) total,
        MAX(Occurred_At__c) lastSeen
      FROM Log__c
      WHERE Occurred_At__c >= :since AND Level__c = :Logger.LEVEL_ERROR
      WITH SYSTEM_MODE
      GROUP BY Source_Type__c, Source_Name__c, Exception_Type__c, Is_Handled__c
      ORDER BY COUNT(Id) DESC
      LIMIT :MAX_ROWS + 1
    ]) {
      if (rows.size() == MAX_ROWS) {
        totals.truncated = true;
        break;
      }
      LogSlackFormatter.Row row = new LogSlackFormatter.Row();
      row.sourceType = (String) grouped.get('sourceType');
      row.sourceName = (String) grouped.get('sourceName');
      row.exceptionType = (String) grouped.get('exceptionType');
      row.isHandled = (Boolean) grouped.get('handled');
      row.total = (Integer) grouped.get('total');
      row.lastSeen = (Datetime) grouped.get('lastSeen');
      rows.add(row);
    }
    return rows;
  }
}
