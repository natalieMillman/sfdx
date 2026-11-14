@IsTest
private class LogPurgeBatchTest {
  @IsTest
  static void logsOlderThanRetentionAreDeleted() {
    LogTestSupport.useSettings('#default-alerts', '#daily', 10);
    Log__c old = LogTestSupport.insertLog(
      'ERROR',
      'Apex',
      'Old',
      null,
      true,
      System.now().addDays(-40)
    );
    Log__c recent = LogTestSupport.insertLog(
      'ERROR',
      'Apex',
      'Recent',
      null,
      true,
      System.now()
    );
    Test.setCreatedDate(old.Id, System.now().addDays(-40));

    Test.startTest();
    new LogPurgeBatch().execute((SchedulableContext) null);
    Test.stopTest();

    List<Log__c> remaining = LogTestSupport.allLogs();
    Assert.areEqual(1, remaining.size());
    Assert.areEqual(recent.Id, remaining[0].Id);
  }
}
