// Schedules the logging jobs. Safe to run again: it replaces existing schedules.
//
// Run it as the logging runtime user (the one with the Logging_Runtime
// permission set), because the daily summary posts to Slack as whoever
// scheduled it:
//   sf apex run --file scripts/apex/schedule-logging-jobs.apex --target-org <alias>

final String SUMMARY_JOB = 'Log Daily Summary';
final String PURGE_JOB = 'Log Purge';

for (CronTrigger existing : [
  SELECT Id
  FROM CronTrigger
  WHERE CronJobDetail.Name IN (:SUMMARY_JOB, :PURGE_JOB)
]) {
  System.abortJob(existing.Id);
}

// Seconds Minutes Hours Day-of-month Month Day-of-week, in the user's time zone.
System.schedule(SUMMARY_JOB, '0 0 8 * * ?', new LogDailySummaryJob());
System.schedule(PURGE_JOB, '0 0 2 * * ?', new LogPurgeBatch());

System.debug(
  'Scheduled: ' + SUMMARY_JOB + ' at 08:00, ' + PURGE_JOB + ' at 02:00'
);
