@IsTest
private class AddOnScopeServiceTest {
  @TestSetup
  static void setup() {
    System.runAs(TestDataFactory.createAddOnUser()) {
      TestDataFactory.createOpportunity(null);
    }
  }

  private static Id opportunityId() {
    return [SELECT Id FROM Opportunity LIMIT 1].Id;
  }

  @IsTest
  static void derivesQuantityPerType() {
    System.runAs(TestDataFactory.addOnUser()) {
      Id oppId = opportunityId();
      List<Add_On__c> addOns = new List<Add_On__c>{
        TestDataFactory.timeTracking(oppId, 12),
        TestDataFactory.stateTax(oppId, 3),
        TestDataFactory.hrConsulting(oppId, 4, 3)
      };

      Test.startTest();
      insert addOns;
      Test.stopTest();

      Map<Id, Add_On__c> saved = new Map<Id, Add_On__c>(
        [SELECT Id, Quantity__c FROM Add_On__c]
      );
      Assert.areEqual(
        12,
        saved.get(addOns[0].Id).Quantity__c.intValue(),
        'Time Tracking = hourly employees'
      );
      Assert.areEqual(
        3,
        saved.get(addOns[1].Id).Quantity__c.intValue(),
        'State Tax = number of states'
      );
      Assert.areEqual(
        7,
        saved.get(addOns[2].Id).Quantity__c.intValue(),
        'HR Consulting = full-time + part-time'
      );
    }
  }

  @IsTest
  static void treatsBlankScopeAsZero() {
    System.runAs(TestDataFactory.addOnUser()) {
      Add_On__c addOn = TestDataFactory.hrConsulting(opportunityId(), 5, null);
      insert addOn;
      Assert.areEqual(
        5,
        [SELECT Quantity__c FROM Add_On__c WHERE Id = :addOn.Id]
          .Quantity__c.intValue(),
        'Blank part-time counts as zero'
      );
    }
  }

  @IsTest
  static void clearsScopeFieldsThatDoNotApplyToType() {
    System.runAs(TestDataFactory.addOnUser()) {
      Add_On__c addOn = TestDataFactory.timeTracking(opportunityId(), 10);
      addOn.Number_of_States__c = 5; // not a Time Tracking field
      insert addOn;

      Add_On__c saved = [
        SELECT Type__c, Number_of_Hourly_Employees__c, Number_of_States__c
        FROM Add_On__c
        WHERE Id = :addOn.Id
      ];
      Assert.isNull(
        saved.Number_of_States__c,
        'Non-applicable scope is cleared on insert'
      );
      Assert.areEqual(
        10,
        saved.Number_of_Hourly_Employees__c.intValue(),
        'Applicable scope is kept'
      );

      saved.Type__c = TestDataFactory.TYPE_STATE_TAX;
      saved.Number_of_States__c = 2;
      update saved;

      saved = [
        SELECT Number_of_Hourly_Employees__c, Number_of_States__c, Quantity__c
        FROM Add_On__c
        WHERE Id = :addOn.Id
      ];
      Assert.isNull(
        saved.Number_of_Hourly_Employees__c,
        'Old scope is cleared when the type changes'
      );
      Assert.areEqual(
        2,
        saved.Quantity__c.intValue(),
        'Quantity follows the new type'
      );
    }
  }

  @IsTest
  static void rejectsTypeWithoutConfiguration() {
    System.runAs(TestDataFactory.addOnUser()) {
      AddOnTypeConfig.useMock(
        new List<Add_On_Type__mdt>{
          new Add_On_Type__mdt(
            DeveloperName = 'Time_Tracking',
            MasterLabel = 'Time Tracking',
            Add_On_Type__c = TestDataFactory.TYPE_TIME_TRACKING,
            Product_Code__c = TestDataFactory.CODE_TIME_TRACKING,
            Quantity_Fields__c = 'Number_of_Hourly_Employees__c'
          )
        }
      );
      Add_On__c addOn = TestDataFactory.hrConsulting(opportunityId(), 1, 1);
      expectDmlError(addOn, AddOnScopeService.UNKNOWN_TYPE_ERROR);
    }
  }

  @IsTest
  static void blocksApprovalWithoutScope() {
    System.runAs(TestDataFactory.addOnUser()) {
      Add_On__c addOn = TestDataFactory.timeTracking(opportunityId(), null);
      addOn.Status__c = AddOnScopeService.STATUS_APPROVED;
      expectDmlError(addOn, 'Enter Number of Hourly Employees');
    }
  }

  @IsTest
  static void blocksNegativeScope() {
    System.runAs(TestDataFactory.addOnUser()) {
      Add_On__c addOn = TestDataFactory.stateTax(opportunityId(), -1);
      expectDmlError(addOn, 'cannot be negative');
    }
  }

  @IsTest
  static void locksTypeOnceApproved() {
    System.runAs(TestDataFactory.addOnUser()) {
      TestDataFactory.createCatalog();
      Add_On__c addOn = TestDataFactory.timeTracking(opportunityId(), 10);
      insert addOn;
      TestDataFactory.approve(addOn);

      expectDmlError(
        new Add_On__c(
          Id = addOn.Id,
          Type__c = TestDataFactory.TYPE_STATE_TAX,
          Number_of_States__c = 2
        ),
        AddOnScopeService.TYPE_LOCKED_ERROR
      );
    }
  }

  @IsTest
  static void allowsTypeChangeBeforeApproval() {
    System.runAs(TestDataFactory.addOnUser()) {
      Add_On__c addOn = TestDataFactory.timeTracking(opportunityId(), 10);
      insert addOn;
      update new Add_On__c(
        Id = addOn.Id,
        Type__c = TestDataFactory.TYPE_HR_CONSULTING,
        Full_Time_Employees__c = 1
      );
      Assert.areEqual(
        TestDataFactory.TYPE_HR_CONSULTING,
        [SELECT Type__c FROM Add_On__c WHERE Id = :addOn.Id].Type__c,
        'Type is editable until approval'
      );
    }
  }

  private static void expectDmlError(Add_On__c addOn, String expectedFragment) {
    try {
      upsert addOn;
      Assert.fail('Expected a DML error containing: ' + expectedFragment);
    } catch (DmlException e) {
      Assert.isTrue(
        e.getMessage().contains(expectedFragment),
        'Expected "' + expectedFragment + '" but got: ' + e.getMessage()
      );
    }
  }
}
