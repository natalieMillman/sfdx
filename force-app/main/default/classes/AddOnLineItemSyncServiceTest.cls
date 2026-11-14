@IsTest
private class AddOnLineItemSyncServiceTest {
  @TestSetup
  static void setup() {
    System.runAs(TestDataFactory.createAddOnUser()) {
      Pricebook2 addOnBook = TestDataFactory.createCatalog();
      TestDataFactory.createOpportunity(addOnBook.Id);
    }
  }

  private static Opportunity opportunity() {
    return [SELECT Id, Pricebook2Id FROM Opportunity LIMIT 1];
  }

  private static Id addOnPriceBookId() {
    return [SELECT Id FROM Pricebook2 WHERE IsStandard = FALSE LIMIT 1].Id;
  }

  @IsTest
  static void approvingCreatesLineItemUnderAddOnPriceBook() {
    System.runAs(TestDataFactory.addOnUser()) {
      Add_On__c addOn = TestDataFactory.timeTracking(opportunity().Id, 12);
      insert addOn;
      Assert.isTrue(
        TestDataFactory.lineItemsFor(addOn.Id).isEmpty(),
        'No product while Interested'
      );

      Test.startTest();
      TestDataFactory.approve(addOn);
      Test.stopTest();

      List<OpportunityLineItem> items = TestDataFactory.lineItemsFor(addOn.Id);
      Assert.areEqual(1, items.size(), 'Exactly one product is created');
      Assert.areEqual(
        TestDataFactory.CODE_TIME_TRACKING,
        items[0].Product2.ProductCode,
        'Product matches the type'
      );
      Assert.areEqual(
        12,
        items[0].Quantity.intValue(),
        'Quantity = hourly employees'
      );
      Assert.areEqual(
        8,
        items[0].UnitPrice.intValue(),
        'List price from the Add-On price book'
      );
      Assert.areEqual(
        addOnPriceBookId(),
        items[0].PricebookEntry.Pricebook2Id,
        'Entry belongs to the Add-On price book'
      );
    }
  }

  @IsTest
  static void creatingAsApprovedCreatesLineItem() {
    System.runAs(TestDataFactory.addOnUser()) {
      Add_On__c addOn = TestDataFactory.stateTax(opportunity().Id, 4);
      addOn.Status__c = AddOnScopeService.STATUS_APPROVED;
      insert addOn;

      List<OpportunityLineItem> items = TestDataFactory.lineItemsFor(addOn.Id);
      Assert.areEqual(1, items.size(), 'Product created on insert');
      Assert.areEqual(4, items[0].Quantity.intValue(), 'Quantity = states');
    }
  }

  @IsTest
  static void repeatedSavesDoNotDuplicate() {
    System.runAs(TestDataFactory.addOnUser()) {
      Add_On__c addOn = TestDataFactory.timeTracking(opportunity().Id, 12);
      insert addOn;
      TestDataFactory.approve(addOn);
      Id originalItemId = TestDataFactory.lineItemsFor(addOn.Id)[0].Id;

      Test.startTest();
      update new Add_On__c(Id = addOn.Id); // nothing changed
      update new Add_On__c(Id = addOn.Id);
      Test.stopTest();

      List<OpportunityLineItem> items = TestDataFactory.lineItemsFor(addOn.Id);
      Assert.areEqual(
        1,
        items.size(),
        'Still one product after repeated saves'
      );
      Assert.areEqual(
        originalItemId,
        items[0].Id,
        'Same product record, not recreated'
      );
    }
  }

  @IsTest
  static void scopeChangeUpdatesQuantityInPlace() {
    System.runAs(TestDataFactory.addOnUser()) {
      Add_On__c addOn = TestDataFactory.hrConsulting(opportunity().Id, 4, 3);
      insert addOn;
      TestDataFactory.approve(addOn);
      Id originalItemId = TestDataFactory.lineItemsFor(addOn.Id)[0].Id;

      update new Add_On__c(Id = addOn.Id, Part_Time_Employees__c = 6);

      List<OpportunityLineItem> items = TestDataFactory.lineItemsFor(addOn.Id);
      Assert.areEqual(1, items.size(), 'Still one product');
      Assert.areEqual(
        originalItemId,
        items[0].Id,
        'Existing product updated in place'
      );
      Assert.areEqual(
        10,
        items[0].Quantity.intValue(),
        'Quantity = 4 full-time + 6 part-time'
      );
    }
  }

  @IsTest
  static void rejectingAfterApprovalDeletesLineItem() {
    System.runAs(TestDataFactory.addOnUser()) {
      Add_On__c addOn = TestDataFactory.timeTracking(opportunity().Id, 12);
      insert addOn;
      TestDataFactory.approve(addOn);
      Assert.areEqual(
        1,
        TestDataFactory.lineItemsFor(addOn.Id).size(),
        'Precondition: product exists'
      );

      update new Add_On__c(
        Id = addOn.Id,
        Status__c = AddOnScopeService.STATUS_REJECTED
      );

      Assert.isTrue(
        TestDataFactory.lineItemsFor(addOn.Id).isEmpty(),
        'Product removed on rejection'
      );
    }
  }

  @IsTest
  static void rejectingDirectlyCreatesNothing() {
    System.runAs(TestDataFactory.addOnUser()) {
      Add_On__c addOn = TestDataFactory.timeTracking(opportunity().Id, 12);
      insert addOn;
      update new Add_On__c(
        Id = addOn.Id,
        Status__c = AddOnScopeService.STATUS_REJECTED
      );
      Assert.isTrue(
        TestDataFactory.lineItemsFor(addOn.Id).isEmpty(),
        'Rejected Add-Ons never get a product'
      );
    }
  }

  @IsTest
  static void reopeningApprovedAddOnRemovesLineItem() {
    System.runAs(TestDataFactory.addOnUser()) {
      Add_On__c addOn = TestDataFactory.timeTracking(opportunity().Id, 12);
      insert addOn;
      TestDataFactory.approve(addOn);

      update new Add_On__c(
        Id = addOn.Id,
        Status__c = AddOnScopeService.STATUS_IN_PROGRESS
      );

      Assert.isTrue(
        TestDataFactory.lineItemsFor(addOn.Id).isEmpty(),
        'Only approved Add-Ons own a product'
      );
    }
  }

  @IsTest
  static void deletingApprovedAddOnDeletesLineItem() {
    System.runAs(TestDataFactory.addOnUser()) {
      Add_On__c addOn = TestDataFactory.timeTracking(opportunity().Id, 12);
      insert addOn;
      TestDataFactory.approve(addOn);
      Id itemId = TestDataFactory.lineItemsFor(addOn.Id)[0].Id;

      delete addOn;

      Assert.areEqual(
        0,
        [SELECT COUNT() FROM OpportunityLineItem WHERE Id = :itemId],
        'Product deleted with its Add-On'
      );
    }
  }

  @IsTest
  static void undeletingApprovedAddOnRecreatesLineItem() {
    System.runAs(TestDataFactory.addOnUser()) {
      Add_On__c addOn = TestDataFactory.timeTracking(opportunity().Id, 12);
      insert addOn;
      TestDataFactory.approve(addOn);
      delete addOn;

      undelete addOn;

      List<OpportunityLineItem> items = TestDataFactory.lineItemsFor(addOn.Id);
      Assert.areEqual(1, items.size(), 'Product recreated on undelete');
      Assert.areEqual(
        12,
        items[0].Quantity.intValue(),
        'Quantity restored from the Add-On'
      );
    }
  }

  @IsTest
  static void setsOpportunityPriceBookWhenMissing() {
    System.runAs(TestDataFactory.addOnUser()) {
      Opportunity opp = opportunity();
      opp.Pricebook2Id = null;
      update opp;
      Add_On__c addOn = TestDataFactory.timeTracking(opp.Id, 3);
      insert addOn;

      TestDataFactory.approve(addOn);

      Assert.areEqual(
        addOnPriceBookId(),
        [SELECT Pricebook2Id FROM Opportunity WHERE Id = :opp.Id].Pricebook2Id,
        'Opportunity now uses the Add-On price book'
      );
      Assert.areEqual(
        1,
        TestDataFactory.lineItemsFor(addOn.Id).size(),
        'Product created'
      );
    }
  }

  @IsTest
  static void rejectsOpportunityOnDifferentPriceBook() {
    System.runAs(TestDataFactory.addOnUser()) {
      Opportunity opp = opportunity();
      opp.Pricebook2Id = Test.getStandardPricebookId();
      update opp;
      Add_On__c addOn = TestDataFactory.timeTracking(opp.Id, 3);
      insert addOn;

      expectApprovalError(addOn, 'different price book');
      Assert.isTrue(
        TestDataFactory.lineItemsFor(addOn.Id).isEmpty(),
        'No product created'
      );
    }
  }

  @IsTest
  static void errorsWhenPriceBookEntryIsMissing() {
    System.runAs(TestDataFactory.addOnUser()) {
      PricebookEntry entry = [
        SELECT Id
        FROM PricebookEntry
        WHERE
          Pricebook2Id = :addOnPriceBookId()
          AND Product2.ProductCode = :TestDataFactory.CODE_TIME_TRACKING
      ];
      entry.IsActive = false;
      update as system entry;
      Add_On__c addOn = TestDataFactory.timeTracking(opportunity().Id, 3);
      insert addOn;

      expectApprovalError(addOn, 'No active price book entry');
      Assert.isFalse(
        AddOnLineItemSyncService.isSyncing,
        'Sync flag is always reset'
      );
    }
  }

  @IsTest
  static void errorsWhenPriceBookIsMissing() {
    System.runAs(TestDataFactory.addOnUser()) {
      Pricebook2 book = new Pricebook2(
        Id = addOnPriceBookId(),
        IsActive = false
      );
      update as system book;
      Add_On__c addOn = TestDataFactory.timeTracking(opportunity().Id, 3);
      insert addOn;

      expectApprovalError(addOn, 'was not found');
    }
  }

  @IsTest
  static void bulkApprovalStaysWithinLimits() {
    System.runAs(TestDataFactory.addOnUser()) {
      Id oppId = opportunity().Id;
      List<Add_On__c> addOns = new List<Add_On__c>();
      for (Integer i = 0; i < 200; i++) {
        Integer variant = Math.mod(i, 3);
        if (variant == 0) {
          addOns.add(TestDataFactory.timeTracking(oppId, i + 1));
        } else if (variant == 1) {
          addOns.add(TestDataFactory.stateTax(oppId, i + 1));
        } else {
          addOns.add(TestDataFactory.hrConsulting(oppId, i, 1));
        }
      }
      insert addOns;
      List<Add_On__c> approvals = new List<Add_On__c>();
      for (Add_On__c addOn : addOns) {
        approvals.add(
          new Add_On__c(
            Id = addOn.Id,
            Status__c = AddOnScopeService.STATUS_APPROVED
          )
        );
      }

      Test.startTest();
      update approvals;
      Integer queriesUsed = Limits.getQueries();
      Test.stopTest();

      Assert.areEqual(
        200,
        [
          SELECT COUNT()
          FROM OpportunityLineItem
          WHERE Add_On__c IN :addOns
        ],
        'One product per approved Add-On'
      );
      Assert.isTrue(
        queriesUsed <= 10,
        'Sync uses a constant number of queries; used ' + queriesUsed
      );
    }
  }

  private static void expectApprovalError(
    Add_On__c addOn,
    String expectedFragment
  ) {
    try {
      TestDataFactory.approve(addOn);
      Assert.fail('Expected a DML error containing: ' + expectedFragment);
    } catch (DmlException e) {
      Assert.isTrue(
        e.getMessage().contains(expectedFragment),
        'Expected "' + expectedFragment + '" but got: ' + e.getMessage()
      );
    }
  }
}
