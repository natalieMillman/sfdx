@IsTest
private class LogFlowErrorActionTest {
  @IsTest
  static void faultPathIsLoggedAgainstTheFlow() {
    LogTestSupport.noAlertRules();
    LogFlowErrorAction.Request request = new LogFlowErrorAction.Request();
    request.flowApiName = 'Order_Fulfilment';
    request.faultMessage = 'This error occurred when the flow tried to create records';
    request.recordId = UserInfo.getUserId();
    request.feature = 'Orders';

    Test.startTest();
    LogFlowErrorAction.log(new List<LogFlowErrorAction.Request>{ request });
    Test.getEventBus().deliver();
    Test.stopTest();

    Log__c log = LogTestSupport.onlyLog();
    Assert.areEqual('Flow', log.Source_Type__c);
    Assert.areEqual('Order_Fulfilment', log.Source_Name__c);
    Assert.areEqual('FlowFault', log.Exception_Type__c);
    Assert.areEqual(request.faultMessage, log.Message__c);
    Assert.areEqual(UserInfo.getUserId(), log.Record_Id__c);
    Assert.areEqual('Orders', log.Feature__c);
  }

  @IsTest
  static void blankFaultMessageGetsADefault() {
    LogTestSupport.noAlertRules();
    LogFlowErrorAction.Request request = new LogFlowErrorAction.Request();
    request.flowApiName = 'Order_Fulfilment';

    Test.startTest();
    LogFlowErrorAction.log(new List<LogFlowErrorAction.Request>{ request });
    Test.getEventBus().deliver();
    Test.stopTest();

    Assert.areEqual(
      'The flow took a fault path',
      LogTestSupport.onlyLog().Message__c
    );
  }

  @IsTest
  static void onlyFlowsNamedInARuleAlert() {
    LogTestSupport.useSettings('#default-alerts', '#daily', 10);
    LogAlertRules.useMock(
      new List<Log_Alert_Rule__mdt>{
        LogTestSupport.rule('Flow', 'Order_Fulfilment', false, '#orders', 15)
      }
    );
    LogTestSupport.slackSucceeds();
    LogFlowErrorAction.Request critical = new LogFlowErrorAction.Request();
    critical.flowApiName = 'Order_Fulfilment';
    critical.faultMessage = 'Could not create the order';
    LogFlowErrorAction.Request minor = new LogFlowErrorAction.Request();
    minor.flowApiName = 'Update_Nickname';
    minor.faultMessage = 'Could not update the contact';

    Test.startTest();
    LogFlowErrorAction.log(
      new List<LogFlowErrorAction.Request>{ critical, minor }
    );
    Test.getEventBus().deliver();
    Test.stopTest();

    Map<String, Log__c> byFlow = new Map<String, Log__c>();
    for (Log__c log : LogTestSupport.allLogs()) {
      byFlow.put(log.Source_Name__c, log);
    }
    Assert.areEqual('Sent', byFlow.get('Order_Fulfilment').Alert_Status__c);
    Assert.areEqual('None', byFlow.get('Update_Nickname').Alert_Status__c);
    Assert.areEqual(1, LogTestSupport.slackRequests.size());
    Assert.areEqual('#orders', LogTestSupport.slackChannel(0));
    Assert.isTrue(
      LogTestSupport.slackText(0)
        .contains('*Flow failed* in `Order_Fulfilment`')
    );
  }
}
