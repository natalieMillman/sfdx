/**
 * Org-wide logging switches, read from the Log_Settings.Default custom
 * metadata record. Falls back to safe defaults when the record is missing.
 */
public with sharing class LogSettings {
  private static final String RECORD_NAME = 'Default';
  private static final Integer DEFAULT_RETENTION_DAYS = 30;
  private static final Integer DEFAULT_MAX_ALERTS = 10;

  private static Log_Settings__mdt settings;

  @TestVisible
  private static void useMock(Log_Settings__mdt record) {
    settings = record;
  }

  public static Boolean isEnabled() {
    return get().Is_Enabled__c != false;
  }

  public static String defaultAlertChannel() {
    return get().Default_Alert_Channel__c;
  }

  public static String dailySummaryChannel() {
    return get().Daily_Summary_Channel__c;
  }

  public static Integer retentionDays() {
    Decimal days = get().Retention_Days__c;
    return days == null || days < 1 ? DEFAULT_RETENTION_DAYS : days.intValue();
  }

  public static Integer maxAlertsPerBatch() {
    Decimal max = get().Max_Alerts_Per_Batch__c;
    return max == null || max < 1 ? DEFAULT_MAX_ALERTS : max.intValue();
  }

  private static Log_Settings__mdt get() {
    if (settings == null) {
      settings = Log_Settings__mdt.getInstance(RECORD_NAME);
      if (settings == null) {
        settings = new Log_Settings__mdt(Is_Enabled__c = true);
      }
    }
    return settings;
  }
}
