@IsTest
private class LogDailySummaryJobTest {
  static {
    LogTestSupport.noAlertRules();
    LogTestSupport.useSettings('#default-alerts', '#daily', 10);
  }

  @IsTest
  static void summaryTabulatesTheLast24Hours() {
    Datetime now = System.now();
    LogTestSupport.insertLog(
      'ERROR',
      'Apex',
      'AddOnTriggerHandler',
      'System.DmlException',
      false,
      now.addHours(-1)
    );
    LogTestSupport.insertLog(
      'ERROR',
      'Apex',
      'AddOnTriggerHandler',
      'System.DmlException',
      false,
      now.addHours(-2)
    );
    LogTestSupport.insertLog(
      'ERROR',
      'Integration',
      'BillingApi',
      null,
      true,
      now.addHours(-3)
    );
    LogTestSupport.insertLog(
      'WARN',
      'Apex',
      'Quiet',
      null,
      true,
      now.addHours(-3)
    );
    LogTestSupport.insertLog(
      'ERROR',
      'Apex',
      'TooOld',
      'System.DmlException',
      false,
      now.addHours(-30)
    );
    Log__c alerted = LogTestSupport.allLogs()[0];
    alerted.Alert_Status__c = 'Sent';
    Database.update(alerted, AccessLevel.SYSTEM_MODE);
    LogTestSupport.slackSucceeds();

    Test.startTest();
    SlackClient.Result result = LogDailySummaryJob.send(now);
    Test.stopTest();

    Assert.isTrue(result.ok);
    Assert.areEqual(1, LogTestSupport.slackRequests.size());
    Assert.areEqual('#daily', LogTestSupport.slackChannel(0));
    String text = LogTestSupport.slackText(0);
    Assert.isTrue(
      text.contains(
        '3 errors, 2 unhandled, 2 distinct failures. Alerts: 1 sent, 0 failed. 1 warnings.'
      ),
      text
    );
    List<String> lines = text.split('\n');
    Assert.isTrue(
      lines[4].startsWith('    2  Apex: AddOnTriggerHandler'),
      lines[4]
    );
    Assert.isTrue(lines[4].contains('DmlException'), lines[4]);
    Assert.isTrue(lines[4].contains(' yes '), lines[4]);
    Assert.isTrue(
      lines[5].startsWith('    1  Integration: BillingApi'),
      lines[5]
    );
    Assert.isFalse(text.contains('TooOld'), 'Older than 24 hours is left out');
    Assert.isFalse(
      text.contains('Quiet'),
      'Warnings are counted, not tabulated'
    );
  }

  @IsTest
  static void scheduledRunPostsThroughAQueueable() {
    LogTestSupport.insertLog(
      'ERROR',
      'Apex',
      'MyClass',
      'System.DmlException',
      false,
      System.now()
    );
    LogTestSupport.slackSucceeds();

    Test.startTest();
    new LogDailySummaryJob().execute((SchedulableContext) null);
    Test.stopTest();

    Assert.areEqual(1, LogTestSupport.slackRequests.size());
    Assert.isTrue(LogTestSupport.slackText(0).contains('Apex: MyClass'));
  }

  @IsTest
  static void quietDayStillPosts() {
    LogTestSupport.slackSucceeds();

    Test.startTest();
    LogDailySummaryJob.send(System.now());
    Test.stopTest();

    Assert.areEqual(1, LogTestSupport.slackRequests.size());
    Assert.isTrue(
      LogTestSupport.slackText(0).contains('No errors were logged.')
    );
  }

  @IsTest
  static void onlyTheMostFrequentRowsAreShown() {
    Datetime now = System.now();
    List<Log__c> logs = new List<Log__c>();
    for (Integer i = 0; i < LogDailySummaryJob.MAX_ROWS + 2; i++) {
      logs.add(
        new Log__c(
          Level__c = 'ERROR',
          Source_Type__c = 'Apex',
          Source_Name__c = 'Class' + i,
          Exception_Type__c = 'System.DmlException',
          Is_Handled__c = false,
          Occurred_At__c = now.addMinutes(-i),
          Fingerprint__c = 'fp' + i,
          Alert_Status__c = 'None'
        )
      );
    }
    Database.insert(logs, AccessLevel.SYSTEM_MODE);
    LogTestSupport.slackSucceeds();

    Test.startTest();
    LogDailySummaryJob.send(now);
    Test.stopTest();

    String text = LogTestSupport.slackText(0);
    Assert.isTrue(
      text.contains('27 errors, 27 unhandled, 27 distinct failures'),
      text
    );
    Assert.isTrue(text.contains('Showing the 25 most frequent.'), text);
  }

  @IsTest
  static void undeliveredSummaryIsLoggedWithoutAlerting() {
    LogTestSupport.insertLog(
      'ERROR',
      'Apex',
      'MyClass',
      'System.DmlException',
      false,
      System.now()
    );
    LogTestSupport.slackRejects('not_in_channel');

    Test.startTest();
    SlackClient.Result result = LogDailySummaryJob.send(System.now());
    Test.getEventBus().deliver();
    Test.stopTest();

    Assert.isFalse(result.ok);
    Log__c failure;
    for (Log__c log : LogTestSupport.allLogs()) {
      if (log.Source_Type__c == 'Logging') {
        failure = log;
      }
    }
    Assert.isNotNull(failure, 'The failure should be logged');
    Assert.areEqual('LogDailySummaryJob', failure.Source_Name__c);
    Assert.isTrue(
      failure.Message__c.contains('not_in_channel'),
      failure.Message__c
    );
    Assert.areEqual('None', failure.Alert_Status__c);
  }
}
