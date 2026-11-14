/**
 * Logs batch Apex failures reported by the platform as BatchApexErrorEvent.
 * Only batch classes that implement Database.RaisesPlatformEvents raise it.
 */
public without sharing class AsyncFailureHandler {
  private static final Integer MAX_SCOPE_EXCERPT = 2000;

  public static void handleBatchErrors(List<BatchApexErrorEvent> events) {
    try {
      Set<Id> jobIds = new Set<Id>();
      for (BatchApexErrorEvent event : events) {
        jobIds.add(event.AsyncApexJobId);
      }
      Map<Id, AsyncApexJob> jobs = new Map<Id, AsyncApexJob>(
        [
          SELECT Id, ApexClass.Name
          FROM AsyncApexJob
          WHERE Id IN :jobIds
          WITH SYSTEM_MODE
        ]
      );
      for (BatchApexErrorEvent event : events) {
        AsyncApexJob job = jobs.get(event.AsyncApexJobId);
        Logger.Entry entry = new Logger.Entry();
        entry.sourceType = Logger.SOURCE_BATCH;
        entry.sourceName = job == null ||
          job.ApexClass == null
          ? 'Unknown batch'
          : job.ApexClass.Name;
        entry.isHandled = false;
        entry.exceptionType = event.ExceptionType;
        entry.message = event.Message;
        entry.stackTrace = event.StackTrace;
        entry.details =
          'Job ' +
          event.AsyncApexJobId +
          ', phase ' +
          event.Phase +
          '\nScope: ' +
          (event.JobScope == null
            ? ''
            : event.JobScope.left(MAX_SCOPE_EXCERPT));
        Logger.add(entry);
      }
      Logger.flush();
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Could not log batch failure: ' + e.getMessage()
      );
    }
  }
}
