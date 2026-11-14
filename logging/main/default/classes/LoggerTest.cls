@IsTest
private class LoggerTest {
  static {
    LogTestSupport.noAlertRules();
  }

  @IsTest
  static void handledExceptionBecomesLogRow() {
    Test.startTest();
    try {
      Integer zero = 0;
      Integer boom = 1 / zero;
    } catch (Exception e) {
      Logger.error('LoggerTest.handled', e);
    }
    Assert.areEqual(1, Logger.buffer.size(), 'error() should only buffer');
    Logger.flush();
    Test.getEventBus().deliver();
    Test.stopTest();

    Log__c log = onlyLog();
    Assert.areEqual('ERROR', log.Level__c);
    Assert.areEqual('Apex', log.Source_Type__c);
    Assert.areEqual('LoggerTest.handled', log.Source_Name__c);
    Assert.areEqual('System.MathException', log.Exception_Type__c);
    Assert.isTrue(log.Is_Handled__c, 'A caught exception is handled');
    Assert.isTrue(
      log.Message__c.contains('Divide by 0'),
      'Message should carry the exception message'
    );
    Assert.areEqual(UserInfo.getUserId(), log.User__c);
    Assert.isNotNull(log.Fingerprint__c, 'Fingerprint should be set');
    Assert.isNotNull(log.Occurred_At__c, 'Occurred At should be set');
  }

  @IsTest
  static void unhandledPublishesWithoutFlush() {
    Test.startTest();
    Logger.unhandled(
      Logger.SOURCE_QUEUEABLE,
      'SomeJob',
      new IllegalArgumentException('bad input')
    );
    Assert.isTrue(Logger.buffer.isEmpty(), 'unhandled() should flush');
    Test.getEventBus().deliver();
    Test.stopTest();

    Log__c log = onlyLog();
    Assert.isFalse(log.Is_Handled__c, 'Entry should be marked unhandled');
    Assert.areEqual('Queueable', log.Source_Type__c);
    Assert.areEqual('SomeJob', log.Source_Name__c);
  }

  @IsTest
  static void causeChainIsKeptInStackTrace() {
    Exception root = new IllegalArgumentException('root cause');
    Exception wrapper = new CalloutException('wrapper');
    wrapper.initCause(root);

    Test.startTest();
    Logger.unhandled('LoggerTest.cause', wrapper);
    Test.getEventBus().deliver();
    Test.stopTest();

    Assert.isTrue(
      onlyLog()
        .Stack_Trace__c.contains(
          'Caused by: System.IllegalArgumentException: root cause'
        ),
      'Stack trace should include the cause'
    );
  }

  @IsTest
  static void messageAndWarnEntriesCarryLevelAndFeature() {
    Test.startTest();
    Logger.setFeature('Billing');
    Logger.error('LoggerTest.message', 'Something failed');
    Logger.warn('LoggerTest.warn', 'Something odd');
    Logger.flush();
    Test.getEventBus().deliver();
    Test.stopTest();

    Map<String, Log__c> bySource = new Map<String, Log__c>();
    for (Log__c log : [
      SELECT Level__c, Source_Name__c, Feature__c, Summary__c
      FROM Log__c
      WITH SYSTEM_MODE
    ]) {
      bySource.put(log.Source_Name__c, log);
    }
    Assert.areEqual(2, bySource.size());
    Assert.areEqual('ERROR', bySource.get('LoggerTest.message').Level__c);
    Assert.areEqual('WARN', bySource.get('LoggerTest.warn').Level__c);
    Assert.areEqual('Billing', bySource.get('LoggerTest.warn').Feature__c);
    Assert.areEqual(
      'Something failed',
      bySource.get('LoggerTest.message').Summary__c
    );
  }

  @IsTest
  static void integrationErrorKeepsStatusAndDropsQueryString() {
    HttpRequest request = new HttpRequest();
    request.setMethod('POST');
    request.setEndpoint('https://api.example.com/v1/invoices?api_key=secret');
    HttpResponse response = new HttpResponse();
    response.setStatusCode(503);
    response.setStatus('Service Unavailable');
    response.setBody('{"error":"down"}');

    Test.startTest();
    Logger.integrationError('BillingApi.createInvoice', request, response);
    Test.getEventBus().deliver();
    Test.stopTest();

    Log__c log = onlyLog();
    Assert.areEqual('Integration', log.Source_Type__c);
    Assert.areEqual('HTTP 503 Service Unavailable', log.Message__c);
    Assert.isTrue(
      log.Details__c.contains('POST https://api.example.com/v1/invoices'),
      'Details should name the method and endpoint'
    );
    Assert.isFalse(
      log.Details__c.contains('secret'),
      'Query string must not be logged'
    );
    Assert.isTrue(
      log.Details__c.contains('{"error":"down"}'),
      'Details should include the response excerpt'
    );
  }

  @IsTest
  static void integrationExceptionIsLogged() {
    HttpRequest request = new HttpRequest();
    request.setMethod('GET');
    request.setEndpoint('https://api.example.com/v1/ping');

    Test.startTest();
    Logger.integrationError(
      'BillingApi.ping',
      request,
      new CalloutException('Read timed out')
    );
    Test.getEventBus().deliver();
    Test.stopTest();

    Log__c log = onlyLog();
    Assert.areEqual('Integration', log.Source_Type__c);
    Assert.areEqual('System.CalloutException', log.Exception_Type__c);
    Assert.areEqual('Read timed out', log.Message__c);
  }

  @IsTest
  static void longValuesAreTruncatedNotRejected() {
    Logger.Entry entry = new Logger.Entry();
    entry.sourceName = 'x'.repeat(400);
    entry.message = 'm'.repeat(40000);

    Test.startTest();
    Logger.add(entry);
    Logger.flush();
    Test.getEventBus().deliver();
    Test.stopTest();

    Log__c log = onlyLog();
    Assert.areEqual(255, log.Source_Name__c.length());
    Assert.areEqual(32000, log.Message__c.length());
  }

  @IsTest
  static void nothingIsLoggedWhenDisabled() {
    LogSettings.useMock(new Log_Settings__mdt(Is_Enabled__c = false));

    Test.startTest();
    Logger.unhandled('LoggerTest.disabled', new IllegalArgumentException('x'));
    Test.getEventBus().deliver();
    Test.stopTest();

    Assert.areEqual(0, [SELECT COUNT() FROM Log__c WITH SYSTEM_MODE]);
  }

  @IsTest
  static void nullEntryAndEmptyFlushAreIgnored() {
    Test.startTest();
    Logger.add(null);
    Logger.flush();
    Logger.error('LoggerTest.nullException', (Exception) null);
    Logger.flush();
    Test.getEventBus().deliver();
    Test.stopTest();

    Assert.areEqual(1, [SELECT COUNT() FROM Log__c WITH SYSTEM_MODE]);
  }

  @IsTest
  static void userWithNoLoggingPermissionsCanStillLog() {
    Profile minimal = [
      SELECT Id
      FROM Profile
      WHERE Name IN ('Minimum Access - Salesforce', 'Standard User')
      WITH SYSTEM_MODE
      ORDER BY Name
      LIMIT 1
    ];
    User restricted = new User(
      Alias = 'nolog',
      Email = 'nolog@example.com',
      EmailEncodingKey = 'UTF-8',
      LastName = 'NoLog',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = minimal.Id,
      TimeZoneSidKey = 'America/New_York',
      Username = 'nolog' + Math.abs(Crypto.getRandomInteger()) + '@example.com'
    );

    Test.startTest();
    System.runAs(restricted) {
      Logger.error('LoggerTest.restricted', 'Logged by a restricted user');
      Logger.flush();
    }
    Test.getEventBus().deliver();
    Test.stopTest();

    Log__c log = onlyLog();
    Assert.areEqual('LoggerTest.restricted', log.Source_Name__c);
    Assert.areEqual(
      restricted.Id,
      log.User__c,
      'The log should name the user who hit the error'
    );
  }

  @IsTest
  static void logSurvivesRollback() {
    Test.startTest();
    Savepoint sp = Database.setSavepoint();
    Logger.error('LoggerTest.rollback', 'Logged before rollback');
    Logger.flush();
    Database.rollback(sp);
    Test.getEventBus().deliver();
    Test.stopTest();

    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM Log__c
        WHERE Source_Name__c = 'LoggerTest.rollback'
        WITH SYSTEM_MODE
      ],
      'A published log must outlive the rollback'
    );
  }

  private static Log__c onlyLog() {
    List<Log__c> logs = [
      SELECT
        Level__c,
        Source_Type__c,
        Source_Name__c,
        Exception_Type__c,
        Is_Handled__c,
        Message__c,
        Summary__c,
        Stack_Trace__c,
        Details__c,
        Feature__c,
        User__c,
        Fingerprint__c,
        Occurred_At__c
      FROM Log__c
      WITH SYSTEM_MODE
    ];
    Assert.areEqual(1, logs.size(), 'Expected exactly one log row');
    return logs[0];
  }
}
