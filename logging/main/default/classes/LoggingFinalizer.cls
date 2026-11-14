/**
 * Logs a Queueable that dies with an unhandled exception.
 *
 * In the Queueable's execute method, before anything else:
 *   System.attachFinalizer(new LoggingFinalizer('MyQueueable'));
 */
public without sharing class LoggingFinalizer implements Finalizer {
  private final String jobName;

  public LoggingFinalizer(String jobName) {
    this.jobName = jobName;
  }

  public void execute(FinalizerContext context) {
    if (context.getResult() != ParentJobResult.UNHANDLED_EXCEPTION) {
      return;
    }
    Logger.Entry entry = Logger.entryFor(
      Logger.SOURCE_QUEUEABLE,
      jobName,
      context.getException()
    );
    entry.isHandled = false;
    entry.details = 'Job ' + context.getAsyncApexJobId();
    Logger.add(entry);
    Logger.flush();
  }
}
