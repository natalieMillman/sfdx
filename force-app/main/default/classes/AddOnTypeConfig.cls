public with sharing class AddOnTypeConfig {
  private static Map<String, Add_On_Type__mdt> configsByType;
  private static Set<String> allScopeFields;

  @TestVisible
  private static void useMock(List<Add_On_Type__mdt> records) {
    configsByType = new Map<String, Add_On_Type__mdt>();
    for (Add_On_Type__mdt config : records) {
      configsByType.put(config.Add_On_Type__c, config);
    }
    allScopeFields = null;
  }

  public static Boolean isKnown(String addOnType) {
    return addOnType != null && getConfigsByType().containsKey(addOnType);
  }

  public static Add_On_Type__mdt getFor(String addOnType) {
    return getConfigsByType().get(addOnType);
  }

  public static List<String> getQuantityFields(String addOnType) {
    List<String> fields = new List<String>();
    Add_On_Type__mdt config = getFor(addOnType);
    if (config != null && String.isNotBlank(config.Quantity_Fields__c)) {
      for (String field : config.Quantity_Fields__c.split(',')) {
        if (String.isNotBlank(field)) {
          fields.add(field.trim());
        }
      }
    }
    return fields;
  }

  public static Set<String> getAllScopeFields() {
    if (allScopeFields == null) {
      allScopeFields = new Set<String>();
      for (String addOnType : getConfigsByType().keySet()) {
        allScopeFields.addAll(getQuantityFields(addOnType));
      }
    }
    return allScopeFields;
  }

  private static Map<String, Add_On_Type__mdt> getConfigsByType() {
    if (configsByType == null) {
      configsByType = new Map<String, Add_On_Type__mdt>();
      for (Add_On_Type__mdt config : Add_On_Type__mdt.getAll().values()) {
        configsByType.put(config.Add_On_Type__c, config);
      }
    }
    return configsByType;
  }
}
