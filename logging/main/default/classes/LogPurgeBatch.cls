/**
 * Deletes logs older than the retention period in Log_Settings.Default.
 * Schedule it with scripts/apex/schedule-logging-jobs.apex.
 */
public without sharing class LogPurgeBatch implements Database.Batchable<SObject>, Schedulable, Database.RaisesPlatformEvents {
  private static final Integer BATCH_SIZE = 2000;

  public void execute(SchedulableContext context) {
    Database.executeBatch(new LogPurgeBatch(), BATCH_SIZE);
  }

  public Database.QueryLocator start(Database.BatchableContext context) {
    Datetime cutoff = System.now().addDays(-LogSettings.retentionDays());
    return Database.getQueryLocator(
      [SELECT Id FROM Log__c WHERE CreatedDate < :cutoff WITH SYSTEM_MODE]
    );
  }

  public void execute(Database.BatchableContext context, List<Log__c> scope) {
    List<Log__c> deleted = new List<Log__c>();
    List<Database.DeleteResult> results = Database.delete(
      scope,
      false,
      AccessLevel.SYSTEM_MODE
    );
    for (Integer i = 0; i < results.size(); i++) {
      if (results[i].isSuccess()) {
        deleted.add(scope[i]);
      }
    }
    if (!deleted.isEmpty()) {
      Database.emptyRecycleBin(deleted);
    }
  }

  public void finish(Database.BatchableContext context) {
  }
}
