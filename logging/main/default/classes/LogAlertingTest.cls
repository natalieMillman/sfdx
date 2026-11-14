/**
 * End-to-end tests of real-time alerting: event -> Log__c -> rule match ->
 * SlackAlertQueueable -> Slack callout -> outcome written back.
 */
@IsTest
private class LogAlertingTest {
  private static void useUnhandledApexRule(Integer throttleMinutes) {
    LogTestSupport.useSettings('#default-alerts', '#daily', 10);
    LogAlertRules.useMock(
      new List<Log_Alert_Rule__mdt>{
        LogTestSupport.rule('Apex', null, true, '#apex-alerts', throttleMinutes)
      }
    );
  }

  @IsTest
  static void unhandledExceptionIsSentToSlack() {
    useUnhandledApexRule(15);
    LogTestSupport.slackSucceeds();

    Test.startTest();
    Logger.unhandled(
      'OrderService.submit',
      new IllegalArgumentException('bad order')
    );
    Test.getEventBus().deliver();
    Test.stopTest();

    Log__c log = LogTestSupport.onlyLog();
    Assert.areEqual('Sent', log.Alert_Status__c);
    Assert.areEqual('#apex-alerts', log.Alert_Channel__c);
    Assert.isNotNull(log.Alerted_At__c);
    Assert.isNull(log.Alert_Error__c);
    Assert.areEqual(1, LogTestSupport.slackRequests.size());
    Assert.areEqual('#apex-alerts', LogTestSupport.slackChannel(0));
    Assert.isTrue(
      LogTestSupport.slackText(0).contains('`OrderService.submit`'),
      LogTestSupport.slackText(0)
    );
    Assert.isTrue(LogTestSupport.slackText(0).contains('bad order'));
  }

  @IsTest
  static void handledErrorIsLoggedButNotSent() {
    useUnhandledApexRule(15);
    LogTestSupport.slackSucceeds();

    Test.startTest();
    Logger.error(
      'OrderService.submit',
      new IllegalArgumentException('bad order')
    );
    Logger.flush();
    Test.getEventBus().deliver();
    Test.stopTest();

    Assert.areEqual('None', LogTestSupport.onlyLog().Alert_Status__c);
    Assert.areEqual(0, LogTestSupport.slackRequests.size());
  }

  @IsTest
  static void repeatsInOneBurstSendOneAlertWithACount() {
    useUnhandledApexRule(15);
    LogTestSupport.slackSucceeds();
    List<Log_Event__e> events = new List<Log_Event__e>();
    for (Integer i = 0; i < 50; i++) {
      events.add(
        LogTestSupport.event(
          'Apex',
          'OrderService.submit',
          'System.DmlException',
          'Row ' + i + ' is locked',
          false
        )
      );
    }

    Test.startTest();
    EventBus.publish(events);
    Test.getEventBus().deliver();
    Test.stopTest();

    Assert.areEqual(
      1,
      LogTestSupport.slackRequests.size(),
      'One alert for the burst'
    );
    Assert.isTrue(
      LogTestSupport.slackText(0).contains('50 occurrences'),
      LogTestSupport.slackText(0)
    );
    Assert.areEqual(1, countWithStatus('Sent'));
    Assert.areEqual(49, countWithStatus('Suppressed'));
  }

  @IsTest
  static void failureThatAlertedRecentlyIsSuppressed() {
    useUnhandledApexRule(15);
    LogTestSupport.slackSucceeds();
    Log_Event__e event = LogTestSupport.event(
      'Apex',
      'OrderService.submit',
      'System.DmlException',
      'Row 1 is locked',
      false
    );
    Log__c earlier = LogTestSupport.insertLog(
      'ERROR',
      'Apex',
      'OrderService.submit',
      'System.DmlException',
      false,
      System.now()
    );
    earlier.Fingerprint__c = LogEventHandler.fingerprintOf(event);
    earlier.Alert_Status__c = 'Sent';
    Database.update(earlier, AccessLevel.SYSTEM_MODE);

    Test.startTest();
    EventBus.publish(event);
    Test.getEventBus().deliver();
    Test.stopTest();

    Assert.areEqual(0, LogTestSupport.slackRequests.size(), 'Throttled');
    Assert.areEqual(1, countWithStatus('Suppressed'));
  }

  @IsTest
  static void zeroThrottleAlertsEveryTime() {
    useUnhandledApexRule(0);
    LogTestSupport.slackSucceeds();
    Log_Event__e event = LogTestSupport.event(
      'Apex',
      'OrderService.submit',
      'System.DmlException',
      'Row 1 is locked',
      false
    );
    Log__c earlier = LogTestSupport.insertLog(
      'ERROR',
      'Apex',
      'OrderService.submit',
      'System.DmlException',
      false,
      System.now()
    );
    earlier.Fingerprint__c = LogEventHandler.fingerprintOf(event);
    earlier.Alert_Status__c = 'Sent';
    Database.update(earlier, AccessLevel.SYSTEM_MODE);

    Test.startTest();
    EventBus.publish(event);
    Test.getEventBus().deliver();
    Test.stopTest();

    Assert.areEqual(1, LogTestSupport.slackRequests.size());
  }

  @IsTest
  static void alertsOverTheCapAreRolledIntoOneMessage() {
    LogTestSupport.useSettings('#default-alerts', '#daily', 2);
    LogAlertRules.useMock(
      new List<Log_Alert_Rule__mdt>{
        LogTestSupport.rule('Apex', null, true, null, 15)
      }
    );
    LogTestSupport.slackSucceeds();
    List<Log_Event__e> events = new List<Log_Event__e>();
    for (String source : new List<String>{ 'A', 'B', 'C', 'D' }) {
      events.add(
        LogTestSupport.event(
          'Apex',
          source,
          'System.DmlException',
          'Failed',
          false
        )
      );
    }

    Test.startTest();
    EventBus.publish(events);
    Test.getEventBus().deliver();
    Test.stopTest();

    Assert.areEqual(
      3,
      LogTestSupport.slackRequests.size(),
      'Two alerts and a roll-up'
    );
    Assert.areEqual('#default-alerts', LogTestSupport.slackChannel(0));
    Assert.isTrue(
      LogTestSupport.slackText(2).contains('2 more failures'),
      LogTestSupport.slackText(2)
    );
    Assert.areEqual(2, countWithStatus('Sent'));
    Assert.areEqual(2, countWithStatus('Suppressed'));
  }

  @IsTest
  static void slackRejectionIsRecordedOnTheLog() {
    useUnhandledApexRule(15);
    LogTestSupport.slackRejects('channel_not_found');

    Test.startTest();
    Logger.unhandled(
      'OrderService.submit',
      new IllegalArgumentException('bad order')
    );
    Test.getEventBus().deliver();
    Test.stopTest();

    Log__c log = LogTestSupport.onlyLog();
    Assert.areEqual('Failed', log.Alert_Status__c);
    Assert.areEqual('Slack error: channel_not_found', log.Alert_Error__c);
    Assert.isNull(log.Alerted_At__c);
  }

  @IsTest
  static void missingChannelFailsWithoutCallingSlack() {
    LogTestSupport.useSettings(null, null, 10);
    LogAlertRules.useMock(
      new List<Log_Alert_Rule__mdt>{
        LogTestSupport.rule('Apex', null, true, null, 15)
      }
    );
    LogTestSupport.slackSucceeds();

    Test.startTest();
    Logger.unhandled(
      'OrderService.submit',
      new IllegalArgumentException('bad order')
    );
    Test.getEventBus().deliver();
    Test.stopTest();

    Log__c log = LogTestSupport.onlyLog();
    Assert.areEqual('Failed', log.Alert_Status__c);
    Assert.areEqual('No Slack channel configured', log.Alert_Error__c);
    Assert.areEqual(0, LogTestSupport.slackRequests.size());
  }

  @IsTest
  static void integrationFailureAlertsEvenWhenHandled() {
    LogTestSupport.useSettings('#default-alerts', '#daily', 10);
    LogAlertRules.useMock(
      new List<Log_Alert_Rule__mdt>{
        LogTestSupport.rule('Integration', null, false, '#integrations', 15)
      }
    );
    LogTestSupport.slackSucceeds();
    HttpRequest request = new HttpRequest();
    request.setMethod('POST');
    request.setEndpoint('https://api.example.com/v1/invoices');
    HttpResponse response = new HttpResponse();
    response.setStatusCode(500);

    Test.startTest();
    Logger.integrationError('BillingApi.createInvoice', request, response);
    Test.getEventBus().deliver();
    Test.stopTest();

    Assert.areEqual('Sent', LogTestSupport.onlyLog().Alert_Status__c);
    Assert.areEqual('#integrations', LogTestSupport.slackChannel(0));
    Assert.isTrue(
      LogTestSupport.slackText(0).contains('*Integration failure*')
    );
  }

  @IsTest
  static void alertingFailureKeepsTheLogAndRecordsItself() {
    useUnhandledApexRule(15);
    LogTestSupport.slackSucceeds();
    LogEventHandler.failDispatch = true;

    Test.startTest();
    Logger.unhandled(
      'OrderService.submit',
      new IllegalArgumentException('bad order')
    );
    Test.getEventBus().deliver();
    Test.stopTest();

    List<Log__c> logs = LogTestSupport.allLogs();
    Assert.areEqual(
      2,
      logs.size(),
      'The original log plus one about the pipeline'
    );
    Map<String, Log__c> byType = new Map<String, Log__c>();
    for (Log__c log : logs) {
      byType.put(log.Source_Type__c, log);
    }
    Assert.areEqual('OrderService.submit', byType.get('Apex').Source_Name__c);
    Assert.areEqual(
      'LogEventHandler.dispatchAlerts',
      byType.get('Logging').Source_Name__c
    );
    Assert.areEqual(0, LogTestSupport.slackRequests.size(), 'No alert loop');
  }

  private static Integer countWithStatus(String status) {
    return [
      SELECT COUNT()
      FROM Log__c
      WHERE Alert_Status__c = :status
      WITH SYSTEM_MODE
    ];
  }
}
