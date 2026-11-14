@IsTest
private class LogAlertRulesTest {
  @IsTest
  static void unhandledOnlyRuleIgnoresHandledErrors() {
    LogAlertRules.useMock(
      new List<Log_Alert_Rule__mdt>{
        LogTestSupport.rule('Apex', null, true, '#alerts', 15)
      }
    );

    Assert.isNotNull(
      LogAlertRules.match(log('ERROR', 'Apex', 'MyClass', false))
    );
    Assert.isNull(LogAlertRules.match(log('ERROR', 'Apex', 'MyClass', true)));
    Assert.isNull(LogAlertRules.match(log('ERROR', 'Flow', 'My_Flow', false)));
  }

  @IsTest
  static void sourceTypeListMatchesAnyListedType() {
    LogAlertRules.useMock(
      new List<Log_Alert_Rule__mdt>{
        LogTestSupport.rule(
          'Batch, queueable ,Schedulable',
          null,
          false,
          null,
          15
        )
      }
    );

    Assert.isNotNull(LogAlertRules.match(log('ERROR', 'Batch', 'A', true)));
    Assert.isNotNull(
      LogAlertRules.match(log('ERROR', 'Queueable', 'B', false))
    );
    Assert.isNull(LogAlertRules.match(log('ERROR', 'Integration', 'C', false)));
  }

  @IsTest
  static void blankSourceTypesMatchAnything() {
    LogAlertRules.useMock(
      new List<Log_Alert_Rule__mdt>{
        LogTestSupport.rule(null, null, false, null, 15)
      }
    );

    Assert.isNotNull(
      LogAlertRules.match(log('ERROR', 'Integration', 'X', true))
    );
  }

  @IsTest
  static void namedRuleWinsOverGeneralRule() {
    Log_Alert_Rule__mdt general = LogTestSupport.rule(
      'Flow',
      null,
      false,
      '#general',
      15
    );
    Log_Alert_Rule__mdt exact = LogTestSupport.rule(
      'Flow',
      'Order_Fulfilment',
      false,
      '#orders',
      15
    );
    Log_Alert_Rule__mdt prefix = LogTestSupport.rule(
      'Flow',
      'Billing_*',
      false,
      '#billing',
      15
    );
    LogAlertRules.useMock(
      new List<Log_Alert_Rule__mdt>{ general, exact, prefix }
    );

    Assert.areEqual(
      '#orders',
      LogAlertRules.match(log('ERROR', 'Flow', 'order_fulfilment', true))
        .Slack_Channel__c,
      'Exact names match without regard to case'
    );
    Assert.areEqual(
      '#billing',
      LogAlertRules.match(log('ERROR', 'Flow', 'Billing_Invoice_Sync', true))
        .Slack_Channel__c,
      'A trailing * matches by prefix'
    );
    Assert.areEqual(
      '#general',
      LogAlertRules.match(log('ERROR', 'Flow', 'Something_Else', true))
        .Slack_Channel__c
    );
  }

  @IsTest
  static void namedRuleDoesNotMatchBlankSource() {
    LogAlertRules.useMock(
      new List<Log_Alert_Rule__mdt>{
        LogTestSupport.rule('Flow', 'Order_Fulfilment', false, null, 15)
      }
    );

    Assert.isNull(LogAlertRules.match(log('ERROR', 'Flow', null, true)));
  }

  @IsTest
  static void warningsAndPipelineFailuresNeverAlert() {
    LogAlertRules.useMock(
      new List<Log_Alert_Rule__mdt>{
        LogTestSupport.rule(null, null, false, null, 15)
      }
    );

    Assert.isNull(LogAlertRules.match(log('WARN', 'Apex', 'MyClass', false)));
    Assert.isNull(
      LogAlertRules.match(
        log('ERROR', 'Logging', 'SlackAlertQueueable', false)
      ),
      'The logging pipeline must not alert about itself'
    );
  }

  @IsTest
  static void inactiveRuleIsIgnored() {
    Log_Alert_Rule__mdt rule = LogTestSupport.rule(
      'Apex',
      null,
      false,
      null,
      15
    );
    rule.Is_Active__c = false;
    LogAlertRules.useMock(new List<Log_Alert_Rule__mdt>{ rule });

    Assert.isNull(LogAlertRules.match(log('ERROR', 'Apex', 'MyClass', false)));
  }

  @IsTest
  static void channelAndThrottleFallBackToDefaults() {
    LogTestSupport.useSettings('#default-alerts', '#daily', 10);
    Log_Alert_Rule__mdt bare = LogTestSupport.rule(
      'Apex',
      null,
      false,
      null,
      null
    );
    Log_Alert_Rule__mdt specific = LogTestSupport.rule(
      'Apex',
      null,
      false,
      '#team',
      0
    );

    Assert.areEqual('#default-alerts', LogAlertRules.channelFor(bare));
    Assert.areEqual(15, LogAlertRules.throttleMinutesFor(bare));
    Assert.areEqual('#team', LogAlertRules.channelFor(specific));
    Assert.areEqual(0, LogAlertRules.throttleMinutesFor(specific));
  }

  @IsTest
  static void shippedRulesCoverUnhandledApexAsyncAndIntegrations() {
    Assert.isNotNull(
      LogAlertRules.match(log('ERROR', 'Apex', 'AnyClass', false)),
      'Unhandled Apex should alert'
    );
    Assert.isNull(
      LogAlertRules.match(log('ERROR', 'Apex', 'AnyClass', true)),
      'Handled Apex should not alert'
    );
    Assert.isNotNull(
      LogAlertRules.match(log('ERROR', 'Batch', 'AnyBatch', false))
    );
    Assert.isNotNull(
      LogAlertRules.match(log('ERROR', 'Queueable', 'AnyJob', false))
    );
    Assert.isNotNull(
      LogAlertRules.match(log('ERROR', 'Integration', 'AnyApi', true))
    );
  }

  private static Log__c log(
    String level,
    String sourceType,
    String sourceName,
    Boolean isHandled
  ) {
    return new Log__c(
      Level__c = level,
      Source_Type__c = sourceType,
      Source_Name__c = sourceName,
      Is_Handled__c = isHandled
    );
  }
}
