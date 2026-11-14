@IsTest
private class AddOnTypeConfigTest {
  @IsTest
  static void loadsDeployedTypes() {
    Assert.isTrue(
      AddOnTypeConfig.isKnown(TestDataFactory.TYPE_TIME_TRACKING),
      'Time Tracking is configured'
    );
    Assert.isTrue(
      AddOnTypeConfig.isKnown(TestDataFactory.TYPE_STATE_TAX),
      'State Tax Registration is configured'
    );
    Assert.isTrue(
      AddOnTypeConfig.isKnown(TestDataFactory.TYPE_HR_CONSULTING),
      'HR Consulting is configured'
    );
    Assert.areEqual(
      new List<String>{ 'Full_Time_Employees__c', 'Part_Time_Employees__c' },
      AddOnTypeConfig.getQuantityFields(TestDataFactory.TYPE_HR_CONSULTING),
      'HR Consulting sums two fields'
    );
    Assert.areEqual(
      TestDataFactory.CODE_STATE_TAX,
      AddOnTypeConfig.getFor(TestDataFactory.TYPE_STATE_TAX).Product_Code__c,
      'Product code comes from metadata'
    );
    Assert.areEqual(
      4,
      AddOnTypeConfig.getAllScopeFields().size(),
      'Four scope fields across three types'
    );
  }

  @IsTest
  static void unknownTypeHasNoConfiguration() {
    Assert.isFalse(
      AddOnTypeConfig.isKnown('Payroll Concierge'),
      'Unconfigured type is unknown'
    );
    Assert.isFalse(AddOnTypeConfig.isKnown(null), 'Null type is unknown');
    Assert.isNull(
      AddOnTypeConfig.getFor('Payroll Concierge'),
      'No config for unknown type'
    );
    Assert.isTrue(
      AddOnTypeConfig.getQuantityFields('Payroll Concierge').isEmpty(),
      'No fields for unknown type'
    );
  }

  @IsTest
  static void mockReplacesDeployedMetadata() {
    AddOnTypeConfig.useMock(
      new List<Add_On_Type__mdt>{
        new Add_On_Type__mdt(
          DeveloperName = 'Payroll_Concierge',
          MasterLabel = 'Payroll Concierge',
          Add_On_Type__c = 'Payroll Concierge',
          Product_Code__c = 'PAYROLL',
          Quantity_Fields__c = 'Number_of_States__c, Number_of_Hourly_Employees__c'
        )
      }
    );
    Assert.isTrue(
      AddOnTypeConfig.isKnown('Payroll Concierge'),
      'Mocked type is known'
    );
    Assert.isFalse(
      AddOnTypeConfig.isKnown(TestDataFactory.TYPE_TIME_TRACKING),
      'Mock fully replaces deployed types'
    );
    Assert.areEqual(
      new List<String>{
        'Number_of_States__c',
        'Number_of_Hourly_Employees__c'
      },
      AddOnTypeConfig.getQuantityFields('Payroll Concierge'),
      'Fields are trimmed and keep metadata order'
    );
    Assert.areEqual(
      2,
      AddOnTypeConfig.getAllScopeFields().size(),
      'Scope field cache is rebuilt from the mock'
    );
  }
}
