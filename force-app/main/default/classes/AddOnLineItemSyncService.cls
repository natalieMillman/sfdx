public with sharing class AddOnLineItemSyncService {
  public static Boolean isSyncing = false;

  @TestVisible
  private static final String MISSING_ENTRY_ERROR = 'No active price book entry for product code {0} in "{1}". Add the product to that price book and try again.';
  @TestVisible
  private static final String PRICE_BOOK_MISMATCH_ERROR = 'This Opportunity uses a different price book than "{0}". Change the Opportunity price book before approving Add-Ons.';
  @TestVisible
  private static final String REPOINT_ERROR = 'Could not set the Opportunity price book to "{0}": {1}';

  private class Plan {
    Id priceBookId;
    Set<Id> repointedOpportunityIds = new Set<Id>();
    List<Opportunity> opportunityUpdates = new List<Opportunity>();
    List<OpportunityLineItem> inserts = new List<OpportunityLineItem>();
    List<Add_On__c> insertSources = new List<Add_On__c>();
    List<OpportunityLineItem> updates = new List<OpportunityLineItem>();
    List<Add_On__c> updateSources = new List<Add_On__c>();
    List<OpportunityLineItem> deletes = new List<OpportunityLineItem>();
    List<Add_On__c> deleteSources = new List<Add_On__c>();
  }

  public static void sync(List<Add_On__c> addOns) {
    if (isSyncing || addOns == null || addOns.isEmpty()) {
      return;
    }
    Plan plan = new Plan();
    Map<Id, OpportunityLineItem> existingByAddOnId = queryExistingLineItems(
      addOns
    );

    List<Add_On__c> approved = new List<Add_On__c>();
    for (Add_On__c addOn : addOns) {
      if (AddOnScopeService.isApproved(addOn)) {
        approved.add(addOn);
      } else if (existingByAddOnId.containsKey(addOn.Id)) {
        plan.deletes.add(existingByAddOnId.get(addOn.Id));
        plan.deleteSources.add(addOn);
      }
    }
    planApproved(approved, existingByAddOnId, plan);
    execute(plan);
  }

  public static void deleteLineItemsFor(List<Add_On__c> addOns) {
    if (addOns == null || addOns.isEmpty()) {
      return;
    }
    List<OpportunityLineItem> owned = queryExistingLineItems(addOns).values();
    if (owned.isEmpty()) {
      return;
    }
    isSyncing = true;
    try {
      Database.delete(owned, AccessLevel.SYSTEM_MODE);
    } finally {
      isSyncing = false;
    }
  }

  private static void planApproved(
    List<Add_On__c> approved,
    Map<Id, OpportunityLineItem> existingByAddOnId,
    Plan plan
  ) {
    if (approved.isEmpty()) {
      return;
    }
    Map<String, PricebookEntry> entriesByCode;
    try {
      plan.priceBookId = PricebookService.getPricebook().Id;
      entriesByCode = PricebookService.getEntriesByProductCode(
        productCodesOf(approved)
      );
    } catch (PricebookService.PricebookException e) {
      Logger.error('AddOnLineItemSyncService.planApproved', e);
      for (Add_On__c addOn : approved) {
        addOn.addError(e.getMessage());
      }
      return;
    }
    Map<Id, Opportunity> opportunities = new Map<Id, Opportunity>(
      [
        SELECT Id, Pricebook2Id
        FROM Opportunity
        WHERE Id IN :opportunityIdsOf(approved)
        WITH USER_MODE
      ]
    );
    for (Add_On__c addOn : approved) {
      String productCode = productCodeOf(addOn);
      PricebookEntry entry = entriesByCode.get(productCode);
      if (entry == null) {
        addOn.addError(
          String.format(
            MISSING_ENTRY_ERROR,
            new List<String>{ productCode, PricebookService.getPriceBookName() }
          )
        );
      } else if (existingByAddOnId.containsKey(addOn.Id)) {
        planQuantityUpdate(addOn, existingByAddOnId.get(addOn.Id), plan);
      } else {
        planInsert(addOn, entry, opportunities.get(addOn.Opportunity__c), plan);
      }
    }
  }

  private static void planQuantityUpdate(
    Add_On__c addOn,
    OpportunityLineItem existing,
    Plan plan
  ) {
    if (existing.Quantity != addOn.Quantity__c) {
      plan.updates.add(
        new OpportunityLineItem(
          Id = existing.Id,
          Quantity = addOn.Quantity__c.doubleValue()
        )
      );
      plan.updateSources.add(addOn);
    }
  }

  private static void planInsert(
    Add_On__c addOn,
    PricebookEntry entry,
    Opportunity opportunity,
    Plan plan
  ) {
    if (opportunity.Pricebook2Id == null) {
      if (plan.repointedOpportunityIds.add(opportunity.Id)) {
        plan.opportunityUpdates.add(
          new Opportunity(Id = opportunity.Id, Pricebook2Id = plan.priceBookId)
        );
      }
    } else if (opportunity.Pricebook2Id != plan.priceBookId) {
      addOn.addError(
        String.format(
          PRICE_BOOK_MISMATCH_ERROR,
          new List<String>{ PricebookService.getPriceBookName() }
        )
      );
      return;
    }
    plan.inserts.add(
      new OpportunityLineItem(
        OpportunityId = addOn.Opportunity__c,
        PricebookEntryId = entry.Id,
        Quantity = addOn.Quantity__c.doubleValue(),
        UnitPrice = entry.UnitPrice,
        Add_On__c = addOn.Id
      )
    );
    plan.insertSources.add(addOn);
  }

  private static void execute(Plan plan) {
    isSyncing = true;
    try {
      Map<Id, String> repointFailures = repointOpportunities(plan);
      List<OpportunityLineItem> inserts = new List<OpportunityLineItem>();
      List<Add_On__c> insertSources = new List<Add_On__c>();
      for (Integer i = 0; i < plan.inserts.size(); i++) {
        Add_On__c source = plan.insertSources[i];
        if (repointFailures.containsKey(source.Opportunity__c)) {
          source.addError(
            String.format(
              REPOINT_ERROR,
              new List<String>{
                PricebookService.getPriceBookName(),
                repointFailures.get(source.Opportunity__c)
              }
            )
          );
        } else {
          inserts.add(plan.inserts[i]);
          insertSources.add(source);
        }
      }
      if (!inserts.isEmpty()) {
        reportSaveErrors(Database.insert(inserts, false), insertSources);
      }
      if (!plan.updates.isEmpty()) {
        reportSaveErrors(
          Database.update(plan.updates, false),
          plan.updateSources
        );
      }
      if (!plan.deletes.isEmpty()) {
        reportDeleteErrors(
          Database.delete(plan.deletes, false),
          plan.deleteSources
        );
      }
    } finally {
      isSyncing = false;
    }
  }

  private static Map<Id, String> repointOpportunities(Plan plan) {
    Map<Id, String> failures = new Map<Id, String>();
    if (plan.opportunityUpdates.isEmpty()) {
      return failures;
    }
    Database.SaveResult[] results = Database.update(
      plan.opportunityUpdates,
      false
    );
    for (Integer i = 0; i < results.size(); i++) {
      if (!results[i].isSuccess()) {
        failures.put(
          plan.opportunityUpdates[i].Id,
          describe(results[i].getErrors())
        );
      }
    }
    return failures;
  }

  private static Map<Id, OpportunityLineItem> queryExistingLineItems(
    List<Add_On__c> addOns
  ) {
    Map<Id, OpportunityLineItem> byAddOnId = new Map<Id, OpportunityLineItem>();
    Set<Id> addOnIds = new Map<Id, Add_On__c>(addOns).keySet();
    for (OpportunityLineItem item : [
      SELECT Id, Quantity, Add_On__c
      FROM OpportunityLineItem
      WHERE Add_On__c IN :addOnIds
      WITH USER_MODE
    ]) {
      byAddOnId.put(item.Add_On__c, item);
    }
    return byAddOnId;
  }

  private static void reportSaveErrors(
    Database.SaveResult[] results,
    List<Add_On__c> sources
  ) {
    for (Integer i = 0; i < results.size(); i++) {
      if (!results[i].isSuccess()) {
        sources[i].addError(describe(results[i].getErrors()));
      }
    }
  }

  private static void reportDeleteErrors(
    Database.DeleteResult[] results,
    List<Add_On__c> sources
  ) {
    for (Integer i = 0; i < results.size(); i++) {
      if (!results[i].isSuccess()) {
        sources[i].addError(describe(results[i].getErrors()));
      }
    }
  }

  private static String describe(List<Database.Error> errors) {
    List<String> messages = new List<String>();
    for (Database.Error error : errors) {
      messages.add(error.getMessage());
    }
    return String.join(messages, '; ');
  }

  private static String productCodeOf(Add_On__c addOn) {
    Add_On_Type__mdt config = AddOnTypeConfig.getFor(addOn.Type__c);
    return config == null ? null : config.Product_Code__c;
  }

  private static Set<String> productCodesOf(List<Add_On__c> addOns) {
    Set<String> codes = new Set<String>();
    for (Add_On__c addOn : addOns) {
      String code = productCodeOf(addOn);
      if (code != null) {
        codes.add(code);
      }
    }
    return codes;
  }

  private static Set<Id> opportunityIdsOf(List<Add_On__c> addOns) {
    Set<Id> ids = new Set<Id>();
    for (Add_On__c addOn : addOns) {
      ids.add(addOn.Opportunity__c);
    }
    return ids;
  }
}
