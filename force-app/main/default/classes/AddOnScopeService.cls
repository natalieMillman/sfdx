public with sharing class AddOnScopeService {
  public static final String STATUS_INTERESTED = 'Interested';
  public static final String STATUS_IN_PROGRESS = 'In Progress';
  public static final String STATUS_APPROVED = 'Complete - Approved';
  public static final String STATUS_REJECTED = 'Complete - Rejected';

  @TestVisible
  private static final String UNKNOWN_TYPE_ERROR = 'No Add-On Type configuration exists for this type. Ask an administrator to add an Add_On_Type__mdt record.';
  @TestVisible
  private static final String NEGATIVE_SCOPE_ERROR = '{0} cannot be negative.';
  @TestVisible
  private static final String MISSING_SCOPE_ERROR = 'Enter {0} before marking this Add-On Complete - Approved.';
  @TestVisible
  private static final String TYPE_LOCKED_ERROR = 'Type cannot be changed while an Add-On is Complete - Approved. Reject it and create a new Add-On instead.';

  public static Boolean isApproved(Add_On__c addOn) {
    return addOn != null && addOn.Status__c == STATUS_APPROVED;
  }

  public static void apply(
    List<Add_On__c> records,
    Map<Id, Add_On__c> oldRecords
  ) {
    for (Add_On__c addOn : records) {
      if (!AddOnTypeConfig.isKnown(addOn.Type__c)) {
        addOn.Type__c.addError(UNKNOWN_TYPE_ERROR);
        continue;
      }
      Add_On__c oldAddOn = oldRecords == null ? null : oldRecords.get(addOn.Id);
      clearInapplicableScope(addOn);
      addOn.Quantity__c = deriveQuantity(addOn);
      validate(addOn, oldAddOn);
    }
  }

  public static Decimal deriveQuantity(Add_On__c addOn) {
    Decimal total = 0;
    for (String field : AddOnTypeConfig.getQuantityFields(addOn.Type__c)) {
      Decimal value = (Decimal) addOn.get(field);
      if (value != null) {
        total += value;
      }
    }
    return total;
  }

  private static void clearInapplicableScope(Add_On__c addOn) {
    Set<String> applicable = new Set<String>(
      AddOnTypeConfig.getQuantityFields(addOn.Type__c)
    );
    for (String field : AddOnTypeConfig.getAllScopeFields()) {
      if (!applicable.contains(field)) {
        addOn.put(field, null);
      }
    }
  }

  private static void validate(Add_On__c addOn, Add_On__c oldAddOn) {
    for (String field : AddOnTypeConfig.getQuantityFields(addOn.Type__c)) {
      Decimal value = (Decimal) addOn.get(field);
      if (value != null && value < 0) {
        addOn.addError(
          String.format(
            NEGATIVE_SCOPE_ERROR,
            new List<String>{ labelOf(field) }
          )
        );
        return;
      }
    }
    if (isApproved(addOn) && addOn.Quantity__c <= 0) {
      addOn.addError(
        String.format(
          MISSING_SCOPE_ERROR,
          new List<String>{ scopeLabels(addOn.Type__c) }
        )
      );
      return;
    }
    if (
      oldAddOn != null &&
      isApproved(oldAddOn) &&
      addOn.Type__c != oldAddOn.Type__c
    ) {
      addOn.Type__c.addError(TYPE_LOCKED_ERROR);
    }
  }

  private static String scopeLabels(String addOnType) {
    List<String> labels = new List<String>();
    for (String field : AddOnTypeConfig.getQuantityFields(addOnType)) {
      labels.add(labelOf(field));
    }
    return String.join(labels, ' and ');
  }

  private static String labelOf(String fieldApiName) {
    Schema.SObjectField field = Schema.SObjectType.Add_On__c.fields.getMap()
      .get(fieldApiName.toLowerCase());
    return field == null ? fieldApiName : field.getDescribe().getLabel();
  }
}
