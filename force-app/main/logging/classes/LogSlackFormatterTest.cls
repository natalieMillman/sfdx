@IsTest
private class LogSlackFormatterTest {
  @IsTest
  static void alertNamesSourceExceptionCountAndLink() {
    Log__c log = saved(
      'Apex',
      'AddOnTriggerHandler',
      'System.DmlException',
      false
    );

    String text = LogSlackFormatter.alert(log, 3);

    Assert.isTrue(
      text.contains('*Unhandled Apex exception* in `AddOnTriggerHandler`'),
      text
    );
    Assert.isTrue(
      text.contains('*System.DmlException*: Something failed'),
      text
    );
    Assert.isTrue(text.contains('3 occurrences'), text);
    Assert.isTrue(
      text.contains(
        '<' +
          URL.getOrgDomainUrl().toExternalForm() +
          '/' +
          log.Id +
          '|Open ' +
          log.Name +
          '>'
      ),
      text
    );
  }

  @IsTest
  static void singleOccurrenceOmitsTheCount() {
    Log__c log = saved('Apex', 'MyClass', 'System.DmlException', false);

    Assert.isFalse(LogSlackFormatter.alert(log, 1).contains('occurrences'));
  }

  @IsTest
  static void titleDependsOnSourceType() {
    Assert.isTrue(
      LogSlackFormatter.alert(
          saved('Flow', 'Order_Fulfilment', 'FlowFault', true),
          1
        )
        .contains('*Flow failed*')
    );
    Assert.isTrue(
      LogSlackFormatter.alert(saved('Integration', 'BillingApi', null, true), 1)
        .contains('*Integration failure*')
    );
    Assert.isTrue(
      LogSlackFormatter.alert(
          saved('Batch', 'NightlySync', 'System.LimitException', false),
          1
        )
        .contains('*Batch job failed*')
    );
    Assert.isTrue(
      LogSlackFormatter.alert(
          saved('Apex', 'MyClass', 'System.DmlException', true),
          1
        )
        .contains('*Apex error*')
    );
    Assert.isTrue(
      LogSlackFormatter.alert(saved('Email', 'Odd subject', null, false), 1)
        .contains('*Unrecognised error email*')
    );
  }

  @IsTest
  static void slackMarkupInLoggedTextIsEscaped() {
    Log__c log = saved('Apex', 'My`Class', 'System.DmlException', false);
    log.Summary__c = '<!channel> rate & `limit`';
    log.Feature__c = 'Billing';

    String text = LogSlackFormatter.alert(log, 1);

    Assert.isTrue(text.contains('&lt;!channel&gt; rate &amp; \'limit\''), text);
    Assert.isFalse(
      text.contains('<!channel>'),
      'Raw markup must not reach Slack'
    );
    Assert.isTrue(text.contains('`My\'Class`'), text);
    Assert.isTrue(text.contains('Feature: Billing'), text);
  }

  @IsTest
  static void blankMessageIsShownAsNoMessage() {
    Log__c log = saved('Apex', 'MyClass', null, false);
    log.Summary__c = null;

    Assert.isTrue(LogSlackFormatter.alert(log, 1).contains('(no message)'));
  }

  @IsTest
  static void dailySummaryTabulatesRowsUnderTotals() {
    LogSlackFormatter.Totals totals = new LogSlackFormatter.Totals();
    totals.errors = 14;
    totals.unhandled = 12;
    totals.distinctFailures = 2;
    totals.alertsSent = 3;
    totals.alertsFailed = 1;
    totals.warnings = 4;
    Datetime lastSeen = Datetime.newInstance(2026, 11, 13, 14, 2, 0);
    List<LogSlackFormatter.Row> rows = new List<LogSlackFormatter.Row>{
      row(
        'Apex',
        'AddOnTriggerHandler',
        'System.DmlException',
        false,
        12,
        lastSeen
      ),
      row('Integration', 'BillingApi.createInvoice', null, true, 2, lastSeen)
    };

    String text = LogSlackFormatter.dailySummary(
      totals,
      rows,
      Datetime.newInstance(2026, 11, 14, 8, 0, 0)
    );
    List<String> lines = text.split('\n');

    Assert.isTrue(
      lines[0]
        .startsWith('*Salesforce errors: last 24 hours* (to 14 Nov 08:00'),
      lines[0]
    );
    Assert.areEqual(
      '14 errors, 12 unhandled, 2 distinct failures. Alerts: 3 sent, 1 failed. 4 warnings.',
      lines[1]
    );
    Assert.areEqual('```', lines[2]);
    Assert.areEqual(
      'Count  Source                            Exception               Unh  Last seen',
      lines[3]
    );
    Assert.areEqual(
      '   12  Apex: AddOnTriggerHandler         DmlException            yes  13 Nov 14:02',
      lines[4]
    );
    Assert.areEqual(
      '    2  Integration: BillingApi.creat...  -                        -   13 Nov 14:02',
      lines[5]
    );
    Assert.areEqual('```', lines[6]);
    Assert.isTrue(
      lines[7].contains('/lightning/o/Log__c/list|Open logs in Salesforce>'),
      lines[7]
    );
    Assert.isFalse(text.contains('most frequent'), 'Not truncated');
  }

  @IsTest
  static void dailySummarySaysWhenRowsWereCutOff() {
    LogSlackFormatter.Totals totals = new LogSlackFormatter.Totals();
    totals.errors = 1;
    totals.truncated = true;
    List<LogSlackFormatter.Row> rows = new List<LogSlackFormatter.Row>{
      row('Apex', 'A', 'System.DmlException', false, 1, System.now())
    };

    String text = LogSlackFormatter.dailySummary(totals, rows, System.now());

    Assert.isTrue(text.contains('Showing the 1 most frequent.'), text);
    Assert.isFalse(text.contains('warnings'), 'No warnings to report');
  }

  @IsTest
  static void quietDayStillProducesAMessage() {
    LogSlackFormatter.Totals totals = new LogSlackFormatter.Totals();

    String quiet = LogSlackFormatter.dailySummary(
      totals,
      new List<LogSlackFormatter.Row>(),
      System.now()
    );
    totals.warnings = 2;
    String quietWithWarnings = LogSlackFormatter.dailySummary(
      totals,
      new List<LogSlackFormatter.Row>(),
      System.now()
    );

    Assert.isTrue(quiet.contains('No errors were logged.'), quiet);
    Assert.isFalse(quiet.contains('```'), 'No table on a quiet day');
    Assert.isTrue(quietWithWarnings.contains('2 warnings.'), quietWithWarnings);
  }

  @IsTest
  static void overflowMessageGivesTheCount() {
    String text = LogSlackFormatter.overflow(7);

    Assert.isTrue(text.contains('7 more failures'), text);
    Assert.isTrue(text.contains('/lightning/o/Log__c/list'), text);
  }

  private static Log__c saved(
    String sourceType,
    String sourceName,
    String exceptionType,
    Boolean isHandled
  ) {
    Id logId = LogTestSupport.insertLog(
        'ERROR',
        sourceType,
        sourceName,
        exceptionType,
        isHandled,
        System.now()
      )
      .Id;
    for (Log__c log : LogTestSupport.allLogs()) {
      if (log.Id == logId) {
        return log;
      }
    }
    return null;
  }

  private static LogSlackFormatter.Row row(
    String sourceType,
    String sourceName,
    String exceptionType,
    Boolean isHandled,
    Integer total,
    Datetime lastSeen
  ) {
    LogSlackFormatter.Row row = new LogSlackFormatter.Row();
    row.sourceType = sourceType;
    row.sourceName = sourceName;
    row.exceptionType = exceptionType;
    row.isHandled = isHandled;
    row.total = total;
    row.lastSeen = lastSeen;
    return row;
  }
}
