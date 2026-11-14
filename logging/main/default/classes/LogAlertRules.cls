/**
 * Decides which log entries raise a real-time Slack alert, from the
 * Log_Alert_Rule__mdt records. Only ERROR entries alert, and the logging
 * pipeline's own failures never do, so a broken alert cannot alert about
 * itself.
 */
public with sharing class LogAlertRules {
  private static final Integer DEFAULT_THROTTLE_MINUTES = 15;

  private static List<Log_Alert_Rule__mdt> rules;

  @TestVisible
  private static void useMock(List<Log_Alert_Rule__mdt> records) {
    rules = sortBySpecificity(records);
  }

  /** The first matching rule, most specific first, or null for no alert. */
  public static Log_Alert_Rule__mdt match(Log__c log) {
    if (
      log.Level__c != Logger.LEVEL_ERROR ||
      log.Source_Type__c == Logger.SOURCE_LOGGING
    ) {
      return null;
    }
    for (Log_Alert_Rule__mdt rule : getRules()) {
      if (matches(rule, log)) {
        return rule;
      }
    }
    return null;
  }

  public static String channelFor(Log_Alert_Rule__mdt rule) {
    return String.isBlank(rule.Slack_Channel__c)
      ? LogSettings.defaultAlertChannel()
      : rule.Slack_Channel__c;
  }

  public static Integer throttleMinutesFor(Log_Alert_Rule__mdt rule) {
    Decimal minutes = rule.Throttle_Minutes__c;
    return minutes == null ||
      minutes < 0
      ? DEFAULT_THROTTLE_MINUTES
      : minutes.intValue();
  }

  private static Boolean matches(Log_Alert_Rule__mdt rule, Log__c log) {
    if (rule.Is_Active__c == false) {
      return false;
    }
    if (rule.Unhandled_Only__c == true && log.Is_Handled__c != false) {
      return false;
    }
    return matchesType(rule.Source_Types__c, log.Source_Type__c) &&
      matchesName(rule.Source_Name__c, log.Source_Name__c);
  }

  private static Boolean matchesType(String allowed, String actual) {
    if (String.isBlank(allowed)) {
      return true;
    }
    for (String sourceType : allowed.split(',')) {
      if (sourceType.trim().equalsIgnoreCase(actual)) {
        return true;
      }
    }
    return false;
  }

  private static Boolean matchesName(String pattern, String actual) {
    if (String.isBlank(pattern)) {
      return true;
    }
    if (actual == null) {
      return false;
    }
    String wanted = pattern.trim();
    if (wanted.endsWith('*')) {
      return actual.startsWithIgnoreCase(wanted.removeEnd('*'));
    }
    return wanted.equalsIgnoreCase(actual);
  }

  private static List<Log_Alert_Rule__mdt> getRules() {
    if (rules == null) {
      rules = sortBySpecificity(Log_Alert_Rule__mdt.getAll().values());
    }
    return rules;
  }

  /** Rules that name a source win over catch-all rules for a source type. */
  private static List<Log_Alert_Rule__mdt> sortBySpecificity(
    List<Log_Alert_Rule__mdt> records
  ) {
    List<Log_Alert_Rule__mdt> named = new List<Log_Alert_Rule__mdt>();
    List<Log_Alert_Rule__mdt> general = new List<Log_Alert_Rule__mdt>();
    for (Log_Alert_Rule__mdt rule : records) {
      if (String.isBlank(rule.Source_Name__c)) {
        general.add(rule);
      } else {
        named.add(rule);
      }
    }
    named.addAll(general);
    return named;
  }
}
