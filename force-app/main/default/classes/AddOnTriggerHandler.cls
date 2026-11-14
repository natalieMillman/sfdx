public with sharing class AddOnTriggerHandler {
  public static void handleTransaction(
    System.TriggerOperation operation,
    List<Add_On__c> newRecords,
    Map<Id, Add_On__c> oldRecords
  ) {
    switch on operation {
      when BEFORE_INSERT, BEFORE_UPDATE {
        AddOnScopeService.apply(newRecords, oldRecords);
      }
      when AFTER_INSERT {
        AddOnLineItemSyncService.sync(approvedOnly(newRecords));
      }
      when AFTER_UPDATE {
        AddOnLineItemSyncService.sync(needingSync(newRecords, oldRecords));
      }
      when BEFORE_DELETE {
        AddOnLineItemSyncService.deleteLineItemsFor(newRecords);
      }
      when AFTER_UNDELETE {
        AddOnLineItemSyncService.sync(newRecords);
      }
    }
  }

  private static List<Add_On__c> approvedOnly(List<Add_On__c> records) {
    List<Add_On__c> result = new List<Add_On__c>();
    for (Add_On__c addOn : records) {
      if (AddOnScopeService.isApproved(addOn)) {
        result.add(addOn);
      }
    }
    return result;
  }

  private static List<Add_On__c> needingSync(
    List<Add_On__c> records,
    Map<Id, Add_On__c> oldRecords
  ) {
    List<Add_On__c> result = new List<Add_On__c>();
    for (Add_On__c addOn : records) {
      Add_On__c oldAddOn = oldRecords.get(addOn.Id);
      Boolean statusChanged = addOn.Status__c != oldAddOn.Status__c;
      Boolean scopeChanged = addOn.Quantity__c != oldAddOn.Quantity__c;
      if (
        statusChanged || (scopeChanged && AddOnScopeService.isApproved(addOn))
      ) {
        result.add(addOn);
      }
    }
    return result;
  }
}
