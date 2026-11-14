@IsTest
private class LogEventHandlerTest {
  static {
    LogTestSupport.noAlertRules();
  }

  @IsTest
  static void sameFailureWithDifferentIdsSharesAFingerprint() {
    Log_Event__e first = event(
      'Insert failed for 001000000000001AAA: row 12 is locked'
    );
    Log_Event__e second = event(
      'Insert failed for 001000000000002AAA: row 987 is locked'
    );
    Log_Event__e different = event('Update failed: field is required');

    Assert.areEqual(
      LogEventHandler.fingerprintOf(first),
      LogEventHandler.fingerprintOf(second),
      'Ids and numbers should not change the fingerprint'
    );
    Assert.areNotEqual(
      LogEventHandler.fingerprintOf(first),
      LogEventHandler.fingerprintOf(different),
      'Different failures need different fingerprints'
    );
    Assert.areEqual(64, LogEventHandler.fingerprintOf(first).length());
  }

  @IsTest
  static void fingerprintDependsOnSource() {
    Log_Event__e one = event('Same message');
    Log_Event__e other = event('Same message');
    other.Source_Name__c = 'OtherClass';

    Assert.areNotEqual(
      LogEventHandler.fingerprintOf(one),
      LogEventHandler.fingerprintOf(other)
    );
  }

  @IsTest
  static void eventsWithoutUserOrTimestampStillSave() {
    Log_Event__e bare = new Log_Event__e(
      Level__c = 'ERROR',
      Source_Type__c = 'Email',
      Source_Name__c = 'Unknown',
      User_Id__c = 'not-an-id'
    );

    Test.startTest();
    EventBus.publish(bare);
    Test.getEventBus().deliver();
    Test.stopTest();

    Log__c log = [
      SELECT User__c, Occurred_At__c, Summary__c, Alert_Status__c
      FROM Log__c
      WITH SYSTEM_MODE
    ];
    Assert.isNull(log.User__c, 'An invalid user id is dropped');
    Assert.isNotNull(log.Occurred_At__c, 'Occurred At defaults to now');
    Assert.areEqual('None', log.Alert_Status__c);
  }

  @IsTest
  static void bulkEventsAreAllSaved() {
    List<Log_Event__e> events = new List<Log_Event__e>();
    for (Integer i = 0; i < 200; i++) {
      events.add(event('Failure number ' + i));
    }

    Test.startTest();
    EventBus.publish(events);
    Test.getEventBus().deliver();
    Test.stopTest();

    Assert.areEqual(200, [SELECT COUNT() FROM Log__c WITH SYSTEM_MODE]);
    Assert.areEqual(
      1,
      [SELECT COUNT_DISTINCT(Fingerprint__c) FROM Log__c WITH SYSTEM_MODE][0]
        .get('expr0'),
      'Messages that differ only by a number share one fingerprint'
    );
  }

  @IsTest
  static void persistFailureIsRetriedThenDropped() {
    LogEventHandler.failPersist = true;

    Test.startTest();
    EventBus.publish(event('Will not save'));
    // One delivery plus the retries. None may throw out of the trigger.
    for (Integer i = 0; i <= LogEventHandler.MAX_RETRIES + 1; i++) {
      Test.getEventBus().deliver();
    }
    Test.stopTest();

    Assert.areEqual(0, [SELECT COUNT() FROM Log__c WITH SYSTEM_MODE]);
  }

  private static Log_Event__e event(String message) {
    return new Log_Event__e(
      Level__c = 'ERROR',
      Source_Type__c = 'Apex',
      Source_Name__c = 'SomeClass',
      Exception_Type__c = 'System.DmlException',
      Message__c = message,
      Is_Handled__c = true,
      User_Id__c = UserInfo.getUserId(),
      Occurred_At__c = System.now()
    );
  }
}
