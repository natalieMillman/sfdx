@IsTest
private class AddOnTriggerHandlerTest {
  @IsTest
  static void unexpectedExceptionIsLoggedAndStillThrown() {
    Test.startTest();
    try {
      // A null record list makes the scope service throw.
      AddOnTriggerHandler.handleTransaction(
        System.TriggerOperation.BEFORE_INSERT,
        null,
        null
      );
      Assert.fail('The exception should reach the caller');
    } catch (NullPointerException e) {
      Assert.isNotNull(e.getMessage(), 'The original exception is rethrown');
    }
    Test.getEventBus().deliver();
    Test.stopTest();

    List<Log__c> logs = [
      SELECT Source_Type__c, Source_Name__c, Exception_Type__c, Is_Handled__c
      FROM Log__c
      WITH SYSTEM_MODE
    ];
    Assert.areEqual(1, logs.size(), 'The failure should be logged once');
    Assert.areEqual('Apex', logs[0].Source_Type__c);
    Assert.areEqual('AddOnTriggerHandler', logs[0].Source_Name__c);
    Assert.areEqual('System.NullPointerException', logs[0].Exception_Type__c);
    Assert.isFalse(logs[0].Is_Handled__c, 'It escaped, so it is unhandled');
  }
}
