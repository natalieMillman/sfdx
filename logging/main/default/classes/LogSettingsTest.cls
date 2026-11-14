@IsTest
private class LogSettingsTest {
  @IsTest
  static void shippedDefaultRecordIsRead() {
    Assert.isTrue(LogSettings.isEnabled(), 'Logging ships enabled');
    Assert.isTrue(LogSettings.retentionDays() > 0);
    Assert.isTrue(LogSettings.maxAlertsPerBatch() > 0);
  }

  @IsTest
  static void mockValuesAreReturned() {
    LogSettings.useMock(
      new Log_Settings__mdt(
        Is_Enabled__c = false,
        Default_Alert_Channel__c = '#alerts',
        Daily_Summary_Channel__c = '#daily',
        Retention_Days__c = 7,
        Max_Alerts_Per_Batch__c = 3
      )
    );

    Assert.isFalse(LogSettings.isEnabled());
    Assert.areEqual('#alerts', LogSettings.defaultAlertChannel());
    Assert.areEqual('#daily', LogSettings.dailySummaryChannel());
    Assert.areEqual(7, LogSettings.retentionDays());
    Assert.areEqual(3, LogSettings.maxAlertsPerBatch());
  }

  @IsTest
  static void blankNumbersFallBackToDefaults() {
    LogSettings.useMock(new Log_Settings__mdt(Is_Enabled__c = true));

    Assert.areEqual(30, LogSettings.retentionDays());
    Assert.areEqual(10, LogSettings.maxAlertsPerBatch());
  }
}
