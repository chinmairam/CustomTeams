/**
 * This is a trigger handler class for the Custom Teams object 
 * This class is empty because the trigger events definition are declared in the virtual class TriggerHandler 
 * The actual logic for handling trigger events will be implemented in the TriggerHandler class
 * The trigger events can also be overidden if needed 
*/
/*public with sharing class CustomTeamsTriggerHandler extends TriggerHandler {}*/
/*********************************************************************************************************
 * Class CustomTeamsHandler
 * @description Standalone trigger handler for Custom Teams (does not extend TriggerHandler).
 * Invoke from Custom_Teams__c or from parent-object triggers.
 * Test Class CustomTeamsHandlerTest
 *********************************************************************************************************/
public with sharing class CustomTeamsTriggerHandler {
    public static void run() {
        if (!Trigger.isExecuting) {
            return;
        }

        if (Trigger.isBefore && Trigger.isInsert) {
            beforeInsert((List<Custom_Teams__c>) Trigger.new);
        } else if (Trigger.isAfter && Trigger.isInsert) {
            afterInsert((List<Custom_Teams__c>) Trigger.new);
        } else if (Trigger.isAfter && Trigger.isUpdate) {
            afterUpdate((List<Custom_Teams__c>) Trigger.new, Trigger.oldMap);
        } else if (Trigger.isAfter && Trigger.isDelete) {
            afterDelete((List<Custom_Teams__c>) Trigger.old);
        }
    }

    /**
     * before insert: access check, duplicate / access-level replace, align OwnerId.
     */
    public static void beforeInsert(List<Custom_Teams__c> newList) {
        if (newList == null || newList.isEmpty()) {
            return;
        }
        CustomTeamAutoShareController.validateAccess(newList);
        CustomTeamAutoShareController.preventExactDuplicates(newList);
        CustomTeamAutoShareController.setOwnerFromRelatedRecord(newList);
    }

    /**
     * after insert: create parent manual shares.
     */
    public static void afterInsert(List<Custom_Teams__c> newList) {
        if (newList == null || newList.isEmpty()) {
            return;
        }
        CustomTeamAutoShareController.handleAfterInsert(newList);
    }

    /**
     * after update: refresh shares when member, access, or parent changes.
     */
    public static void afterUpdate(List<Custom_Teams__c> newList, Map<Id, SObject> oldMap) {
        if (newList == null || newList.isEmpty() || oldMap == null || oldMap.isEmpty()) {
            return;
        }
        CustomTeamAutoShareController.handleTeamMemberUpdate(newList, oldMap);
    }

    /**
     * after delete: remove parent manual shares.
     */
    public static void afterDelete(List<Custom_Teams__c> oldList) {
        if (oldList == null || oldList.isEmpty()) {
            return;
        }
        CustomTeamAutoShareController.handleAfterDelete(oldList);
    }

    /**
     * Call from a parent object trigger (Campaign, Order, etc.) after owner change.
     * Usage: CustomTeamsHandler.handleParentOwnerChange(Trigger.new, Trigger.oldMap);
     */
    public static void handleParentOwnerChange(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        CustomTeamAutoShareController.handleOwnerChange(newRecords, oldMap);
    }
}