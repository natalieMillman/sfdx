@IsTest
private class ExceptionEmailHandlerTest {
  static {
    LogTestSupport.noAlertRules();
  }

  private static final String APEX_BODY =
    'Apex script unhandled exception by user/organization: 005000000000001/00D000000000001\n\n' +
    'caused by: System.NullPointerException: Attempt to de-reference a null object\n\n' +
    'Class.AccountService.run: line 12, column 1\n' +
    'Class.AccountController.save: line 40, column 1\n';

  private static final String TRIGGER_BODY =
    'Apex script unhandled trigger exception by user/organization: 005000000000001/00D000000000001\n\n' +
    'AccountTrigger: execution of AfterInsert\n\n' +
    'caused by: System.DmlException: Insert failed. First exception on row 0; first error: REQUIRED_FIELD_MISSING\n\n' +
    'Trigger.AccountTrigger: line 5, column 1\n';

  private static final String BATCH_BODY =
    'Apex script unhandled exception by user/organization: 005000000000001/00D000000000001\n\n' +
    'Failed to process batch for class \'NightlySyncBatch\' for job id \'707000000000001\'\n\n' +
    'caused by: System.LimitException: Too many SOQL queries: 101\n\n' +
    'Class.NightlySyncBatch.execute: line 20, column 1\n';

  private static final String FLOW_BODY =
    'Error element Create_Order (FlowRecordCreate).\n' +
    'Flow Details\nFlow API Name: Order_Fulfilment\nType: Record-Triggered Flow\nVersion: 3\nStatus: Active\n' +
    'Flow Interview Details\nInterview Label: Order Fulfilment 11/13/2026\n' +
    'Error Occurred: This error occurred when the flow tried to create records: REQUIRED_FIELD_MISSING.\n';

  @IsTest
  static void apexExceptionEmailBecomesAnUnhandledLog() {
    Log__c log = handle(
      'Developer script exception from Acme : AccountService : Attempt to de-reference a null object',
      APEX_BODY,
      null
    );

    Assert.areEqual('Apex', log.Source_Type__c);
    Assert.areEqual('AccountService', log.Source_Name__c);
    Assert.areEqual('System.NullPointerException', log.Exception_Type__c);
    Assert.areEqual('Attempt to de-reference a null object', log.Message__c);
    Assert.isFalse(log.Is_Handled__c, 'An emailed exception was not handled');
    Assert.areEqual(
      'Class.AccountService.run: line 12, column 1\nClass.AccountController.save: line 40, column 1',
      log.Stack_Trace__c
    );
    Assert.isTrue(
      log.Details__c.startsWith('Captured from an error email.'),
      log.Details__c
    );
  }

  @IsTest
  static void triggerExceptionEmailNamesTheTrigger() {
    Log__c log = handle(
      'Developer script exception from Acme : AccountTrigger : AccountTrigger: execution of AfterInsert',
      TRIGGER_BODY,
      null
    );

    Assert.areEqual('Apex', log.Source_Type__c);
    Assert.areEqual('AccountTrigger', log.Source_Name__c);
    Assert.areEqual('System.DmlException', log.Exception_Type__c);
    Assert.isTrue(
      log.Message__c.startsWith('Insert failed. First exception on row 0'),
      log.Message__c
    );
    Assert.areEqual(
      'Trigger.AccountTrigger: line 5, column 1',
      log.Stack_Trace__c
    );
  }

  @IsTest
  static void batchFailureEmailIsLoggedAsABatchFailure() {
    Log__c log = handle(
      'Developer script exception from Acme : NightlySyncBatch : Too many SOQL queries: 101',
      BATCH_BODY,
      null
    );

    Assert.areEqual('Batch', log.Source_Type__c);
    Assert.areEqual('NightlySyncBatch', log.Source_Name__c);
    Assert.areEqual('System.LimitException', log.Exception_Type__c);
    Assert.areEqual('Too many SOQL queries: 101', log.Message__c);
  }

  @IsTest
  static void sourceComesFromTheStackWhenTheSubjectHasNone() {
    Log__c log = handle('Developer script exception', APEX_BODY, null);

    Assert.areEqual('AccountService', log.Source_Name__c);
  }

  @IsTest
  static void flowErrorEmailIsLoggedAgainstTheFlow() {
    Log__c log = handle(
      'Error Occurred During Flow "Order_Fulfilment": An unhandled fault has occurred in this flow',
      FLOW_BODY,
      null
    );

    Assert.areEqual('Flow', log.Source_Type__c);
    Assert.areEqual('Order_Fulfilment', log.Source_Name__c);
    Assert.areEqual('FlowFault', log.Exception_Type__c);
    Assert.isTrue(
      log.Message__c.startsWith(
        'This error occurred when the flow tried to create records'
      ),
      log.Message__c
    );
    Assert.isFalse(log.Is_Handled__c);
  }

  @IsTest
  static void flowNameAndMessageFallBackToTheSubject() {
    Log__c log = handle(
      'Error Occurred During Flow "Order_Fulfilment": An unhandled fault has occurred in this flow',
      'No structured details here.',
      null
    );

    Assert.areEqual('Flow', log.Source_Type__c);
    Assert.areEqual('Order_Fulfilment', log.Source_Name__c);
    Assert.areEqual(
      'An unhandled fault has occurred in this flow',
      log.Message__c
    );
  }

  @IsTest
  static void htmlOnlyEmailIsRead() {
    Log__c log = handle(
      'Error Occurred During Flow "Order_Fulfilment": fault',
      null,
      '<html><body><p>Flow API Name: Order_Fulfilment</p><p>Error Occurred: Something broke.</p></body></html>'
    );

    Assert.areEqual('Flow', log.Source_Type__c);
    Assert.areEqual('Order_Fulfilment', log.Source_Name__c);
  }

  @IsTest
  static void unrecognisedEmailIsStillLogged() {
    Log__c log = handle('Something unexpected', 'Free text', null);

    Assert.areEqual('Email', log.Source_Type__c);
    Assert.areEqual('Something unexpected', log.Source_Name__c);
    Assert.isFalse(log.Is_Handled__c);
    Assert.isTrue(log.Details__c.contains('Free text'), log.Details__c);
  }

  @IsTest
  static void emptyEmailIsStillLogged() {
    Log__c log = handle(null, null, null);

    Assert.areEqual('Email', log.Source_Type__c);
    Assert.areEqual('Unrecognised error email', log.Source_Name__c);
  }

  @IsTest
  static void emailIsSkippedWhenTheFailureWasAlreadyLogged() {
    NullPointerException failure = new NullPointerException();
    failure.setMessage('Attempt to de-reference a null object');

    Test.startTest();
    Logger.unhandled('AccountController.save', failure);
    Test.getEventBus().deliver();
    send(
      'Developer script exception from Acme : AccountService : Attempt to de-reference a null object',
      APEX_BODY,
      null
    );
    Test.getEventBus().deliver();
    Test.stopTest();

    Log__c log = LogTestSupport.onlyLog();
    Assert.areEqual(
      'AccountController.save',
      log.Source_Name__c,
      'Only the directly captured log should exist'
    );
  }

  @IsTest
  static void emailsAreAlwaysAccepted() {
    Test.startTest();
    Messaging.InboundEmailResult result = send(
      'Something unexpected',
      'Free text',
      null
    );
    Test.stopTest();

    Assert.isTrue(
      result.success,
      'Rejecting would bounce the email to its sender'
    );
  }

  private static Log__c handle(String subject, String plainText, String html) {
    Test.startTest();
    send(subject, plainText, html);
    Test.getEventBus().deliver();
    Test.stopTest();
    return LogTestSupport.onlyLog();
  }

  private static Messaging.InboundEmailResult send(
    String subject,
    String plainText,
    String html
  ) {
    Messaging.InboundEmail email = new Messaging.InboundEmail();
    email.subject = subject;
    email.plainTextBody = plainText;
    email.htmlBody = html;
    return new ExceptionEmailHandler()
      .handleInboundEmail(email, new Messaging.InboundEnvelope());
  }
}
