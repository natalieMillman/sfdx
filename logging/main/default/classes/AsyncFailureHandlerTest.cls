@IsTest
private class AsyncFailureHandlerTest {
  static {
    LogTestSupport.noAlertRules();
  }

  @IsTest
  static void failingBatchIsLoggedAsUnhandled() {
    try {
      Test.startTest();
      Database.executeBatch(new LogTestFailingBatch());
      Test.stopTest();
    } catch (IllegalArgumentException e) {
      Assert.areEqual('batch blew up', e.getMessage());
    }
    // First delivery: BatchApexErrorEvent. Second: the Log_Event__e it raises.
    Test.getEventBus().deliver();
    Test.getEventBus().deliver();

    Log__c log = LogTestSupport.onlyLog();
    Assert.areEqual('Batch', log.Source_Type__c);
    Assert.areEqual('LogTestFailingBatch', log.Source_Name__c);
    Assert.areEqual('System.IllegalArgumentException', log.Exception_Type__c);
    Assert.areEqual('batch blew up', log.Message__c);
    Assert.isFalse(log.Is_Handled__c, 'A failed batch is unhandled');
    Assert.isTrue(log.Details__c.contains('phase EXECUTE'), log.Details__c);
  }

  @IsTest
  static void unknownJobStillProducesALog() {
    BatchApexErrorEvent event = new BatchApexErrorEvent();

    Test.startTest();
    AsyncFailureHandler.handleBatchErrors(
      new List<BatchApexErrorEvent>{ event }
    );
    Test.getEventBus().deliver();
    Test.stopTest();

    Log__c log = LogTestSupport.onlyLog();
    Assert.areEqual('Batch', log.Source_Type__c);
    Assert.areEqual('Unknown batch', log.Source_Name__c);
  }
}
