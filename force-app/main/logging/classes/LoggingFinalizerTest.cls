@IsTest
private class LoggingFinalizerTest {
  static {
    LogTestSupport.noAlertRules();
  }

  private class FakeContext implements FinalizerContext {
    private final ParentJobResult result;
    private final Exception failure;

    FakeContext(ParentJobResult result, Exception failure) {
      this.result = result;
      this.failure = failure;
    }

    public Id getAsyncApexJobId() {
      return null;
    }

    public Exception getException() {
      return failure;
    }

    public String getRequestId() {
      return 'request-id';
    }

    public ParentJobResult getResult() {
      return result;
    }
  }

  public class FailingJob implements Queueable {
    public void execute(QueueableContext context) {
      System.attachFinalizer(
        new LoggingFinalizer('LoggingFinalizerTest.FailingJob')
      );
      throw new IllegalArgumentException('job blew up');
    }
  }

  @IsTest
  static void unhandledExceptionIsLoggedAsQueueableFailure() {
    Test.startTest();
    new LoggingFinalizer('NightlySyncJob')
      .execute(
        new FakeContext(
          ParentJobResult.UNHANDLED_EXCEPTION,
          new IllegalArgumentException('job blew up')
        )
      );
    Test.getEventBus().deliver();
    Test.stopTest();

    Log__c log = LogTestSupport.onlyLog();
    Assert.areEqual('Queueable', log.Source_Type__c);
    Assert.areEqual('NightlySyncJob', log.Source_Name__c);
    Assert.areEqual('System.IllegalArgumentException', log.Exception_Type__c);
    Assert.areEqual('job blew up', log.Message__c);
    Assert.isFalse(log.Is_Handled__c, 'A dead job is unhandled');
  }

  @IsTest
  static void successfulJobIsNotLogged() {
    Test.startTest();
    new LoggingFinalizer('NightlySyncJob')
      .execute(new FakeContext(ParentJobResult.SUCCESS, null));
    Test.getEventBus().deliver();
    Test.stopTest();

    Assert.areEqual(0, LogTestSupport.allLogs().size());
  }

  @IsTest
  static void finalizerRunsWhenARealQueueableFails() {
    try {
      Test.startTest();
      System.enqueueJob(new FailingJob());
      Test.stopTest();
      Assert.fail('The job should have failed');
    } catch (IllegalArgumentException e) {
      Assert.areEqual('job blew up', e.getMessage());
    }
    Test.getEventBus().deliver();

    Log__c log = LogTestSupport.onlyLog();
    Assert.areEqual('Queueable', log.Source_Type__c);
    Assert.areEqual('LoggingFinalizerTest.FailingJob', log.Source_Name__c);
    Assert.isFalse(log.Is_Handled__c);
  }
}
