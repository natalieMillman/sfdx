/**
 * Builds the Slack text for real-time alerts and for the daily summary table.
 */
public with sharing class LogSlackFormatter {
  private static final Integer MAX_ALERT_MESSAGE = 600;
  private static final Integer SOURCE_WIDTH = 32;
  private static final Integer EXCEPTION_WIDTH = 22;
  private static final String TIME_FORMAT = 'd MMM HH:mm';

  /** One row of the daily table. */
  public class Row {
    public String sourceType;
    public String sourceName;
    public String exceptionType;
    public Boolean isHandled;
    public Integer total;
    public Datetime lastSeen;
  }

  /** Totals shown above the daily table. */
  public class Totals {
    public Integer errors = 0;
    public Integer unhandled = 0;
    public Integer distinctFailures = 0;
    public Integer warnings = 0;
    public Integer alertsSent = 0;
    public Integer alertsFailed = 0;
    public Boolean truncated = false;
  }

  public static String alert(Log__c log, Integer occurrences) {
    List<String> lines = new List<String>();
    lines.add(
      ':rotating_light: *' +
        titleFor(log) +
        '* in `' +
        clean(log.Source_Name__c) +
        '`'
    );

    String summary = String.isBlank(log.Summary__c)
      ? '(no message)'
      : log.Summary__c.abbreviate(MAX_ALERT_MESSAGE);
    lines.add(
      (String.isBlank(log.Exception_Type__c)
        ? ''
        : '*' + clean(log.Exception_Type__c) + '*: ') + clean(summary)
    );

    List<String> facts = new List<String>();
    if (log.User__r != null) {
      facts.add('User: ' + clean(log.User__r.Name));
    }
    if (String.isNotBlank(log.Feature__c)) {
      facts.add('Feature: ' + clean(log.Feature__c));
    }
    if (occurrences != null && occurrences > 1) {
      facts.add(occurrences + ' occurrences');
    }
    if (log.Occurred_At__c != null) {
      facts.add(log.Occurred_At__c.format(TIME_FORMAT + ' z'));
    }
    lines.add(String.join(facts, '  |  '));
    lines.add('<' + recordUrl(log.Id) + '|Open ' + clean(log.Name) + '>');
    return String.join(lines, '\n');
  }

  public static String overflow(Integer suppressed) {
    return ':warning: ' +
      suppressed +
      ' more failures were logged in the same burst and not sent ' +
      'individually. <' +
      listUrl() +
      '|Open logs in Salesforce>';
  }

  public static String dailySummary(
    Totals totals,
    List<Row> rows,
    Datetime until
  ) {
    String title =
      '*Salesforce errors: last 24 hours* (to ' +
      until.format(TIME_FORMAT + ' z') +
      ')';
    if (totals.errors == 0) {
      String quiet = title + '\n:white_check_mark: No errors were logged.';
      return totals.warnings > 0
        ? quiet + ' ' + totals.warnings + ' warnings.'
        : quiet;
    }

    List<String> lines = new List<String>{ title };
    lines.add(
      totals.errors +
        ' errors, ' +
        totals.unhandled +
        ' unhandled, ' +
        totals.distinctFailures +
        ' distinct failures. Alerts: ' +
        totals.alertsSent +
        ' sent, ' +
        totals.alertsFailed +
        ' failed.' +
        (totals.warnings > 0 ? ' ' + totals.warnings + ' warnings.' : '')
    );
    lines.add('```');
    lines.add(
      'Count  ' +
        'Source'.rightPad(SOURCE_WIDTH) +
        '  ' +
        'Exception'.rightPad(EXCEPTION_WIDTH) +
        '  Unh  Last seen'
    );
    for (Row row : rows) {
      lines.add(
        String.valueOf(row.total).leftPad(5) +
          '  ' +
          cell(row.sourceType + ': ' + row.sourceName, SOURCE_WIDTH) +
          '  ' +
          cell(shortType(row.exceptionType), EXCEPTION_WIDTH) +
          '  ' +
          (row.isHandled == false ? 'yes' : ' - ') +
          '  ' +
          (row.lastSeen == null ? '' : row.lastSeen.format(TIME_FORMAT))
      );
    }
    lines.add('```');
    if (totals.truncated) {
      lines.add('Showing the ' + rows.size() + ' most frequent.');
    }
    lines.add('<' + listUrl() + '|Open logs in Salesforce>');
    return String.join(lines, '\n');
  }

  private static String titleFor(Log__c log) {
    String sourceType = log.Source_Type__c;
    if (sourceType == Logger.SOURCE_FLOW) {
      return 'Flow failed';
    }
    if (sourceType == Logger.SOURCE_INTEGRATION) {
      return 'Integration failure';
    }
    if (sourceType == Logger.SOURCE_EMAIL) {
      return 'Unrecognised error email';
    }
    if (sourceType == Logger.SOURCE_APEX) {
      return log.Is_Handled__c == false
        ? 'Unhandled Apex exception'
        : 'Apex error';
    }
    return sourceType + ' job failed';
  }

  private static String shortType(String exceptionType) {
    return String.isBlank(exceptionType)
      ? '-'
      : exceptionType.removeStart('System.');
  }

  private static String cell(String value, Integer width) {
    return clean(value.abbreviate(width)).rightPad(width);
  }

  /** Slack treats &, < and > as markup, and a backtick would end code formatting. */
  private static String clean(String value) {
    return value == null
      ? ''
      : value.replace('&', '&amp;')
          .replace('<', '&lt;')
          .replace('>', '&gt;')
          .replace('`', '\'');
  }

  private static String recordUrl(Id recordId) {
    return URL.getOrgDomainUrl().toExternalForm() + '/' + recordId;
  }

  private static String listUrl() {
    return URL.getOrgDomainUrl().toExternalForm() + '/lightning/o/Log__c/list';
  }
}
