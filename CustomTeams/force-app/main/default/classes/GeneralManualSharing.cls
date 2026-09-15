/*********************************************************************************************************
* Class GeneralManualSharing
* @description This class is used to implement sharing for Custom Teams
* Test Class CustomTeamAutoShareControllerTest
---------------------------------------------------------------------------------------------------------
* Custom Team -  Trigger process when create/update.
**********************************************************************************************************/
public with sharing class GeneralManualSharing {
    public class SharingConfigurationException extends Exception {}
    
    // Caching describe calls to improve performance
    private static Map<String, Schema.DescribeSObjectResult> sObjectDescribeCache = new Map<String, Schema.DescribeSObjectResult>();
    private static Map<String, String> objectNameCache = new Map<String, String>();
    private static Map<String, String> shareObjectNameCache = new Map<String, String>();
    
    /**
     * Create a manual share for a specific record
     * @param shareRequests - contains recordId, userIdOrGroupId, accessLevel
     * @return List<SharingResult>
     */
    // PMD ApexCRUDViolation: *Share objects often report isCreateable() = false for
    // record owners who are still allowed to insert Manual shares.
    @SuppressWarnings('PMD.ApexCRUDViolation')
    public static List<SharingResult> createManualShares(List<Map<String, Object>> shareRequests) {
        List<SObject> shareRecords = new List<SObject>();
        List<SharingResult> results = new List<SharingResult>();
    
        for (Map<String, Object> req : shareRequests) {
            try {
                Id recordId = (Id) req.get('recordId');
                Id userOrGroupId = (Id) req.get('userIdOrGroupId');
                String accessLevel = (String) req.get('accessLevel');

                String objectName = getCachedObjectName(recordId);

                if (!isObjectSharable(objectName)) {
                    throw new SharingConfigurationException('Object ' + objectName + ' does not support manual sharing');
                }

                String shareObjectName = getShareObjectName(objectName);
                SObject shareRecord = createShareRecord(shareObjectName, recordId, userOrGroupId, accessLevel);
                shareRecords.add(shareRecord);
            } catch (Exception e) {
                SharingResult result = new SharingResult();
                result.isSuccess = false;
                result.message = 'Error preparing share record: ' + e.getMessage();
                results.add(result);
                Nebula.Logger.error('Error preparing share record: ' + e.getMessage()).
                    addTag('GeneralManualSharing.createManualShares');
            }
        }
    
        if (!shareRecords.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.insert(shareRecords, false, AccessLevel.SYSTEM_MODE);
            for (Database.SaveResult sr : saveResults) {
                SharingResult result = new SharingResult();
                if (sr.isSuccess()) {
                    result.isSuccess = true;
                    result.message = 'Share created successfully';
                    result.shareRecordId = sr.getId();
                } else {
                    result.isSuccess = false;
                    result.message = 'Failed to create share: ' + String.join(
                        new List<String>{ sr.getErrors()[0].getMessage() }, '; '
                    );
                    Nebula.Logger.error(result.message).
                        addTag('GeneralManualSharing.createManualShares');
                }
                results.add(result);
            }
            Nebula.Logger.saveLog();
        }
    
        return results;
    }
    
    /**
     * Delete manual sharing for a specific record and user/group
     * @param deleteMap - contains recordId, userId 
     * @return void
     */
    // PMD ApexCRUDViolation: querying/deleting *Share rows (RowCause = Manual) is a
    // platform sharing operation. Typical users do not have CRUD on share objects via
    // Schema describe, but owners/managers must still revoke team access.
    @SuppressWarnings('PMD.ApexCRUDViolation')
    public static void deleteManualShares(Map<String, List<Map<String, Id>>> deleteMap) {
        if (deleteMap.isEmpty()) {
            return;
        }
        
        // Collect all data and build query information
        Map<String, Set<Id>> shareObjectToRecordIds = new Map<String, Set<Id>>();
        Map<String, Set<Id>> shareObjectToUserIds = new Map<String, Set<Id>>();
        Map<String, String> shareObjectToParentField = new Map<String, String>();
        
        // Collect all data first without executing any queries
        for (String shareObjectName : deleteMap.keySet()) {
            String parentFieldName = getparentIdFieldName(shareObjectName);
            List<Map<String, Id>> requests = deleteMap.get(shareObjectName);
    
            Set<Id> recordIds = new Set<Id>();
            Set<Id> userIds = new Set<Id>();
    
            // Collect all record IDs and user IDs for this share object type
            for (Map<String, Id> req : requests) {
                recordIds.add(req.get('recordId'));
                userIds.add(req.get('userId'));
            }
            
            if (!recordIds.isEmpty() && !userIds.isEmpty()) {
                shareObjectToRecordIds.put(shareObjectName, recordIds);
                shareObjectToUserIds.put(shareObjectName, userIds);
                shareObjectToParentField.put(shareObjectName, parentFieldName);
            }
        }
        
        // Execute queries - one per share object type 
        List<SObject> allSharesToDelete = new List<SObject>();
        
        for (String shareObjectName : shareObjectToRecordIds.keySet()) {
            deleteShareRecord(shareObjectName, shareObjectToRecordIds, shareObjectToUserIds, shareObjectToParentField, allSharesToDelete);
        }
        
        // Bulk delete all shares at once
        if (!allSharesToDelete.isEmpty()) {
            try {
                Database.delete(allSharesToDelete, false, AccessLevel.SYSTEM_MODE);
                Nebula.Logger.debug('Successfully deleted ' + allSharesToDelete.size() + ' share records').
                    addTag('GeneralManualSharing.deleteManualShares');
                Nebula.Logger.saveLog();
            } catch (Exception e) {
                Nebula.Logger.error('Error deleting share records: ' + e.getMessage()).
                    addTag('GeneralManualSharing.deleteManualShares');
                Nebula.Logger.saveLog();
            }
        }
	}
    
    /**
     * Get cached object name from record ID to avoid repeated describe calls
     * @param recordId
     * @return String
     */
    private static String getCachedObjectName(Id recordId) {
        String cacheKey = String.valueOf(recordId).substring(0, 3); // Use key prefix for caching
        if (!objectNameCache.containsKey(cacheKey)) {
            objectNameCache.put(cacheKey, recordId.getSObjectType().getDescribe().getName());
        }
        return objectNameCache.get(cacheKey);
    }
    
    /**
     * Get cached share object name to avoid repeated describe calls
     * @param objectName
     * @return String
     */
    private static String getCachedShareObjectName(String objectName) {
        if (!shareObjectNameCache.containsKey(objectName)) {
            shareObjectNameCache.put(objectName, getShareObjectName(objectName));
        }
        return shareObjectNameCache.get(objectName);
    }
    
    /**
     * Get cached sObject describe result to avoid repeated describe calls
     * @param objectName
     * @return Schema.DescribeSObjectResult
     */
    private static Schema.DescribeSObjectResult getCachedDescribe(String objectName) {
        if (!sObjectDescribeCache.containsKey(objectName)) {
            sObjectDescribeCache.put(objectName, Schema.getGlobalDescribe().get(objectName).getDescribe());
        }
        return sObjectDescribeCache.get(objectName);
    }
    
    /**
     * Helper method to execute delete query for a specific share object type
     * @param shareObjectName, shareObjectToRecordIds, shareObjectToParentField, allSharesToDelete
     * @return void
     */
    private static void deleteShareRecord(String shareObjectName, 
                                         Map<String, Set<Id>> shareObjectToRecordIds,
                                         Map<String, Set<Id>> shareObjectToUserIds, 
                                         Map<String, String> shareObjectToParentField,
                                         List<SObject> allSharesToDelete) {
        Set<Id> recordIds = shareObjectToRecordIds.get(shareObjectName);
        Set<Id> userIds = shareObjectToUserIds.get(shareObjectName);
        String parentFieldName = shareObjectToParentField.get(shareObjectName);
        
        if (recordIds == null || recordIds.isEmpty() || userIds == null || userIds.isEmpty()) {
            return;
        }
        
        try {
            String query = 'SELECT Id FROM ' + String.escapeSingleQuotes(shareObjectName) +
                           ' WHERE ' + String.escapeSingleQuotes(parentFieldName) + ' IN :recordIds' +
                           ' AND UserOrGroupId IN :userIds' +
                           ' AND RowCause = \'Manual\'';
            
            List<SObject> shares = Database.query(query);
            allSharesToDelete.addAll(shares);
        } catch (Exception e) {
            Nebula.Logger.error('Error executing delete query for ' + shareObjectName + ': ' + e.getMessage()).
                addTag('GeneralManualSharing.deleteShareRecord');
            Nebula.Logger.saveLog();
        }
    }
    
    /**
     * Checks whether an object supports sharing
     * @param objectName Object API Name
     * @return Boolean
     */
    @TestVisible
    private static Boolean isObjectSharable(String objectName) {
        try {
            String shareObjectName = getCachedShareObjectName(objectName);
            getCachedDescribe(shareObjectName); // This will cache the describe result
            return true;
        } catch (Exception e) {
            return false;
        }
    }
    
    /**
     * Get the shared object API name of the object
     * @param objectName Object API Name
     * @return String
     */
    public static String getShareObjectName(String objectName) {
        if (objectName.endsWith('__c')) {
            return objectName.replace('__c', '__Share');
        } else {
            return objectName + 'Share';
        }
    }
    
    /**
     * Create a shared record
     * @param shareObjectName Shared Object API Name
     * @param recordId Record ID
     * @param userIdOrGroupId 
     * @param accessLevel 
     * @return 
     */
    private static SObject createShareRecord(String shareObjectName, Id recordId, Id userIdOrGroupId, String accessLevel) {
        // Get the shared object type using cached describe
        SObject shareRecord = getCachedDescribe(shareObjectName).getSObjectType().newSObject();
        
        // Set the parent record ID field
        String parentFieldName = getparentIdFieldName(shareObjectName);
        shareRecord.put(parentFieldName, recordId);
        
        // Set User/Group fields
        String userOrGroupFieldName = 'UserOrGroupId';
        shareRecord.put(userOrGroupFieldName, userIdOrGroupId);
        
        // Set the Access Level field
        String accessLevelFieldName = getAccessLevelFieldName(shareObjectName);
        shareRecord.put(accessLevelFieldName, accessLevel);
                
        // Set row Cause
        String rowCauseFieldName = 'RowCause';
        if (getCachedDescribe(shareObjectName).fields.getMap().containsKey(rowCauseFieldName)) {
            shareRecord.put(rowCauseFieldName, 'Manual');
        }
        
        return shareRecord;
    }
    
    /**
     * Get the access level field name
     * @param shareObjectName Shared Object API Name
     * @return String
     */
    @TestVisible
    private static String getAccessLevelFieldName(String shareObjectName) {
        // For custom objects, use standard naming conventions
        if (shareObjectName.endsWith('__Share')) {
            return 'AccessLevel';
        }
        
        // For standard objects, use the object name + AccessLevel
        return shareObjectName.replace('Share', 'AccessLevel');
    }
    
    /**
     * Get the access level field name
     * @param shareObjectName Shared Object API Name
     * @return String
     */
    @TestVisible
    private static String getparentIdFieldName(String shareObjectName) {
        // For custom objects, use standard naming conventions
        if (shareObjectName.endsWith('__Share')) {           
            return 'ParentId';
        }
        
        // For standard objects, use the object name + AccessLevel
        return shareObjectName.replace('Share', 'Id');
    }
    
    /**
     * Shared operation result class
     */
    public class SharingResult {
        @AuraEnabled public Boolean isSuccess { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Id shareRecordId { get; set; }
        
        public SharingResult() {
            this.isSuccess = false;
            this.message = '';
            this.shareRecordId = null;
        }
    }
}