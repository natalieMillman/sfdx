trigger AddOnTrigger on Add_On__c(
  before insert,
  before update,
  before delete,
  after insert,
  after update,
  after undelete
) {
  AddOnTriggerHandler.handleTransaction(
    Trigger.operationType,
    Trigger.isDelete ? Trigger.old : Trigger.new,
    Trigger.oldMap
  );
}
