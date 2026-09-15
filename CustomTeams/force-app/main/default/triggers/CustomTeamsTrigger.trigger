trigger CustomTeamsTrigger on Custom_Teams__c(before insert, after insert, after update, after delete) {
    CustomTeamsTriggerHandler.run();
}