/**
 * A batch that always fails, for testing that batch failures are logged.
 * Top level because inner classes cannot be batch jobs.
 */
@IsTest
public class LogTestFailingBatch implements Database.Batchable<SObject>, Database.RaisesPlatformEvents {
  public Iterable<SObject> start(Database.BatchableContext context) {
    return new List<SObject>{ new User(Id = UserInfo.getUserId()) };
  }

  public void execute(Database.BatchableContext context, List<SObject> scope) {
    throw new IllegalArgumentException('batch blew up');
  }

  public void finish(Database.BatchableContext context) {
  }
}
