/*********************************************************************************************************
* Class CustomTeamRelatedListController
* @description Controller for the Custom Team Related List LWC component
* Test Class CustomTeamRelatedListControllerTest
---------------------------------------------------------------------------------------------------------
* Custom Team - Generic LWC component
**********************************************************************************************************/
public with sharing class CustomTeamRelatedListController {
    public static final String NO_CUSTOM_TEAM_DELETE = System.Label.NO_CUSTOM_TEAM_DELETE_ACCESS;
    public static final String NO_CUSTOM_TEAMS_FOUND = System.Label.NO_CUSTOM_TEAMS_FOUND;
    public static final string TEAM_MEMBER_DELETE_SUCCESS = System.Label.TEAM_MEMBER_DELETE_SUCCESS;
    public static final String ERROR_REMOVING_TEAM_MEMBERS = System.Label.ERROR_REMOVING_TEAM_MEMBERS;
    public static final String INSERT_NOTIFY_SUBJECT = System.Label.INSERT_NOTIFY_SUBJECT;
    public static final String INSERT_NOTIFY_BODY = System.Label.INSERT_NOTIFY_BODY;
    public static final String INSERT_EMAIL_SUBJECT = System.Label.INSERT_EMAIL_SUBJECT;
    public static final String INSERT_EMAIL_BODY = System.Label.INSERT_EMAIL_BODY;
    public static final String UPDATE_NOTIFY_SUBJECT = System.Label.UPDATE_NOTIFY_SUBJECT;
    public static final String UPDATE_NOTIFY_BODY_1 = System.Label.UPDATE_NOTIFY_BODY_1;
    public static final String UPDATE_NOTIFY_BODY_2 = System.Label.UPDATE_NOTIFY_BODY_2;
    public static final String DELETE_NOTIFY_SUBJECT = System.Label.DELETE_NOTIFY_SUBJECT;
    public static final String DELETE_NOTIFY_BODY = System.Label.DELETE_NOTIFY_BODY;
    
    /**
     * Wrapper class for data to be displayed in the LWC
     */
    public class MemberWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public Id teamMemberId { get; set; }
        @AuraEnabled public Id ownerId { get; set; }
        @AuraEnabled public String ownerName { get; set; }
        @AuraEnabled public String teamMemberName { get; set; }
        @AuraEnabled public String teamMemberEmail { get; set; }
        @AuraEnabled public String teamRole { get; set; }
        @AuraEnabled public String accessLevel { get; set; }
        @AuraEnabled public String relatedRecordId { get; set; }
        @AuraEnabled public String relatedObjectAPI { get; set; }
    }
    
    @AuraEnabled
    public static void sendNotifications(String action, String memberId, String recordId, String recordName, String objectApiName, String accessLevel) {
        try {
            String objectLabel = objectApiName;
            if (String.isNotBlank(objectApiName)) {
                Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
                if (sObjectType != null) {
                    objectLabel = sObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel();
                }
            }
            
            CustomNotificationType notifyType = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = 'Notify_Sales_Rep' With System_Mode];
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setNotificationTypeId(notifyType.Id);
            notification.setTargetId(recordId);
            
            String subject = '';
            String body = '';
            Set<String> recipients = new Set<String>();
            Boolean triggerEmail = false;
            if(action == 'Insert'){
                subject = INSERT_NOTIFY_SUBJECT;
                body = INSERT_NOTIFY_BODY + ' ' + objectLabel + ' ' + recordName;
                recipients.add(memberId);
                triggerEmail = true;
            } else if (action == 'Update') {
                subject = UPDATE_NOTIFY_SUBJECT;
                body = UPDATE_NOTIFY_BODY_1 + ' ' + objectLabel + ' ' + recordName + ' '+ UPDATE_NOTIFY_BODY_2 + ' ' + accessLevel;
                recipients.add(memberId);
            } else if (action == 'Delete') {
                subject = DELETE_NOTIFY_SUBJECT;
                body = DELETE_NOTIFY_BODY + ' ' + objectLabel + ' ' + recordName;
                recipients.add(memberId);
            }
            
            notification.setTitle(subject);
            notification.setBody(body);
            notification.send(recipients);
            
            if (triggerEmail) {
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setTargetObjectId(memberId);
                mail.setSaveAsActivity(false);
                mail.setSubject(INSERT_EMAIL_SUBJECT + ' ' + objectLabel + ' ' + recordName);
                mail.setPlainTextBody(INSERT_EMAIL_BODY + ' ' + objectLabel + ' ' + recordName);
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{mail});
            }
        } catch (Exception e) {
            Nebula.Logger.error('Notification Error: ' + e.getMessage());
            Nebula.Logger.saveLog();
            return;
        }
    }
    
    /**
     * Fetches Custom Team Records
     * @param recordId
     * @return List<MemberWrapper>
     */
    @AuraEnabled(cacheable = true)
    public static List<MemberWrapper> getTeamMembers(String recordId) {
        try {
            List<MemberWrapper> teamMembers = new List<MemberWrapper>();
            
            List<Custom_Teams__c> teams = [
                SELECT Id, Team_Member__c, Team_Member__r.Name, Team_Member__r.Email,
                Team_Role__c, Access_Level__c, Related_Record_Id__c, Object_API_Name__c,
                OwnerId, Owner.Name
                FROM Custom_Teams__c
                WHERE Related_Record_Id__c =: recordId
                WITH USER_MODE
                ORDER BY Team_Member__r.Name
            ];
            
            for(Custom_Teams__c team: teams) {
                MemberWrapper wrapper = new MemberWrapper();
                wrapper.id = team.id;
                wrapper.teamMemberId = team.Team_Member__c;
                wrapper.teamMemberName = team.Team_Member__r.Name;
                wrapper.teamMemberEmail = team.Team_Member__r.Email;
                wrapper.teamRole = team.Team_Role__c;
                wrapper.accessLevel = team.Access_Level__c;
                wrapper.relatedRecordId = team.Related_Record_Id__c;
                wrapper.relatedObjectAPI = team.Object_API_Name__c;
                wrapper.ownerId = team.OwnerId;
                wrapper.ownerName = team.Owner.Name;
                teamMembers.add(wrapper);
            }
            
            return teamMembers;
        } catch (Exception e) {
            Nebula.Logger.error(e.getMessage(), e).
                addTag('CustomTeamRelatedListController.getTeamMembers');
            Nebula.Logger.saveLog();
            return new List<MemberWrapper>();
        }
    }
    
    /**
     * Deletes a team member from the parent record
     * @param teamIds
     * @return String
     */
    @AuraEnabled
    public static String deleteTeamMembers(List<Id> teamIds) {
        if (teamIds == null || teamIds.isEmpty()) {
            throw new AuraHandledException('Team IDs list is required and cannot be empty.');
        }
        
        if (!Schema.sObjectType.Custom_Teams__c.isDeletable()) {
             throw new AuraHandledException(NO_CUSTOM_TEAM_DELETE);
        }

        try {
            // 1. Query all Custom_Teams__c records to be deleted.
            List<Custom_Teams__c> teamsToDelete = [
                SELECT Id
                FROM Custom_Teams__c
                WHERE Id IN :teamIds
                WITH USER_MODE
            ];
            
            if (!teamsToDelete.isEmpty()) {
                Database.delete(teamsToDelete, false, AccessLevel.USER_MODE);
            } else {
                return NO_CUSTOM_TEAMS_FOUND;
            }

            return TEAM_MEMBER_DELETE_SUCCESS;
        } catch (Exception e) {
            Nebula.Logger.error('Error deleting team members: ' + e.getMessage(), e).
                addTag('CustomTeamRelatedListController.deleteTeamMembers');
            Nebula.Logger.saveLog();
            
            throw new AuraHandledException(ERROR_REMOVING_TEAM_MEMBERS + e.getMessage());
        }
    }
}