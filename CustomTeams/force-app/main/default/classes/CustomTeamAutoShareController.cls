/*********************************************************************************************************
* Class CustomTeamAutoShareController
* @description This class handles core sharing logic and validations for Custom Teams
* Test Class CustomTeamAutoShareControllerTest
---------------------------------------------------------------------------------------------------------
* Custom Team -  Trigger process when create/update.
**********************************************************************************************************/
public with sharing class CustomTeamAutoShareController {
    public static final string NO_TEAM_MANAGE_ACCESS = System.Label.ERROR_TEAM_MANAGE_INSUFFICIENT_ACCESS;
    public static final string ERROR_VALIDATING_PERMISSIONS = System.Label.ERROR_VALIDATING_PERMISSIONS;
    public static final string DUPLICATE_CUSTOM_TEAM = System.Label.DUPLICATE_CUSTOM_TEAM;
    public static final string INFO_MEMBER_ACCESS_START = System.Label.INFO_MEMBER_ACCESS_START;
    public static final string INFO_MEMBER_ACCESS_END = System.Label.INFO_MEMBER_ACCESS_END;
    
    // Cache for describe calls to improve performance
    private static Map<String, String> objectNameCache = new Map<String, String>();
    private static Map<Id, Id> cachedRoleParentMap;
    /**
     * Validates if user can add Custom Team Records or not
     * @param teamMemberList
     * @return void
     */
    public static void validateAccess(List<Custom_Teams__c> teamMemberList){
        Id currentUserId = UserInfo.getUserId();
        Id currentUserProfileId = UserInfo.getProfileId();
        Id currentUserRoleId = UserInfo.getUserRoleId();
        
        if (Schema.sObjectType.Profile.isAccessible()) {
            List<Profile> profileCheck = [
                SELECT Id, Name, PermissionsModifyAllData 
                FROM Profile 
                WHERE Id = :currentUserProfileId
                LIMIT 1
            ];
            
            if (!profileCheck.isEmpty()) {
                Profile p = profileCheck[0];
                if (p.Name == 'System Administrator' || p.PermissionsModifyAllData) {
                    return; // Allow Access
                }
            }
        }
        
        Set<Id> relatedRecordIds = new Set<Id>();
        for (Custom_Teams__c team : teamMemberList) {
            if (String.isNotBlank(team.Related_Record_Id__c)) {
                try {
                    relatedRecordIds.add(Id.valueOf(team.Related_Record_Id__c));
                } catch (Exception e) { continue; }
            }
        }
        
        if (relatedRecordIds.isEmpty())
        {
            return;
        }
        
        Map<Id, Id> recordOwnerMap = getParentRecordOwners(relatedRecordIds);
        
        Set<Id> ownerIds = new Set<Id>(recordOwnerMap.values());
        Map<Id, Id> ownerRoleMap = new Map<Id, Id>();
        if (!ownerIds.isEmpty() && Schema.sObjectType.User.isAccessible()) {
            for(User u : [SELECT Id, UserRoleId FROM User WHERE Id IN :ownerIds]) {
                ownerRoleMap.put(u.Id, u.UserRoleId);
            }
        }
        
        for (Custom_Teams__c team : teamMemberList) {
            if (String.isBlank(team.Related_Record_Id__c)) {
                continue;
            }
            
            try {
                Id recordId = Id.valueOf(team.Related_Record_Id__c);
                Id recordOwnerId = recordOwnerMap.get(recordId);
                
                // Is Current User the Record Owner?
                if (currentUserId == recordOwnerId) {
                    continue; 
                }
                
                // Is Current User in a Higher Role?
                if (currentUserRoleId != null && recordOwnerId != null && ownerRoleMap.get(recordOwnerId) != null) {
                    Id ownerRoleId = ownerRoleMap.get(recordOwnerId);
                    if (isUserRoleHigher(currentUserRoleId, ownerRoleId)) {
                        continue; 
                    }
                }
                
                team.addError(NO_TEAM_MANAGE_ACCESS);
            } catch (Exception e) {
                team.addError(ERROR_VALIDATING_PERMISSIONS + e.getMessage());
            }
        }
    }
    
    /**
     * Helper to dynamically fetch OwnerId from various parent objects
     * @param recordIds
     * @return Map<Id, Id>
     */
    private static Map<Id, Id> getParentRecordOwners(Set<Id> recordIds) {
        Map<Id, Id> recordToOwnerMap = new Map<Id, Id>();
        Map<String, List<Id>> idsByObject = new Map<String, List<Id>>();
        
        for (Id recId : recordIds) {
            String objName = recId.getSObjectType().getDescribe().getName();
            if (!idsByObject.containsKey(objName)) {
                idsByObject.put(objName, new List<Id>());
            }
            idsByObject.get(objName).add(recId);
        }
        
        for (String objName : idsByObject.keySet()) {
            Map<Id, Id> objectOwnerMap = queryOwnersByObjectType(objName, idsByObject.get(objName));
            recordToOwnerMap.putAll(objectOwnerMap);
        }
        
        return recordToOwnerMap;
    }
    
    /**
     * Query owners for a specific object type
     * @param objectName The API name of the object
     * @param recordIds List of record IDs for this object type
     * @return Map<Id, Id> Map of record ID to owner ID
     */
    private static Map<Id, Id> queryOwnersByObjectType(String objectName, List<Id> recordIds) {
        Map<Id, Id> ownerMap = new Map<Id, Id>();
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
        if (objectType == null || !objectType.getDescribe().isAccessible()) {
            return ownerMap;
        }
        
        String query = 'SELECT Id, OwnerId FROM ' + String.escapeSingleQuotes(objectName) +
            ' WHERE Id IN :recordIds WITH USER_MODE';
        try {
            List<SObject> results = Database.query(query);
            for (SObject sobj : results) {
                ownerMap.put((Id)sobj.get('Id'), (Id)sobj.get('OwnerId'));
            }
        } catch (Exception e) {
            Nebula.Logger.error('Error querying owner for object ' + objectName + ': ' + e.getMessage()).
                addTag('CustomTeamAutoShareController.queryOwnersByObjectType');
            Nebula.Logger.saveLog();
        }
        
        return ownerMap;
    }
    
    /**
     * Checks if the currentRole is an ancestor of targetRole in the hierarchy.
     * @param currentRoleId - The Role ID of the Current User
     * @param targetRoleId - The Role ID of the Record Owner
     */
    private static Boolean isUserRoleHigher(Id currentRoleId, Id targetRoleId) {
        if (currentRoleId == null || targetRoleId == null) {
            return false;
        }
        if (currentRoleId == targetRoleId) {
            return false;
        }
        if (!Schema.sObjectType.UserRole.isAccessible()) {
            return false;
        }
        
        if (cachedRoleParentMap == null) {
            cachedRoleParentMap = new Map<Id, Id>();
            for (UserRole ur : [SELECT Id, ParentRoleId FROM UserRole]) {
                cachedRoleParentMap.put(ur.Id, ur.ParentRoleId);
            }
        }
    
        // Climb up from the Target (Owner) until we hit the top or find the Ancestor (User)
        Id currentLevelRoleId = targetRoleId;
        
        while (currentLevelRoleId != null) {
            // Get the parent of the current level
            Id parentId = cachedRoleParentMap.get(currentLevelRoleId);
            
            // If the parent matches the Current User's Role, we found a match!
            if (parentId == currentRoleId) {
                return true;
            }
            
            // Move up one level
            currentLevelRoleId = parentId;
        }
        
        // We reached the top and never found the ancestor
        return false;
    }
	
	/**
	 * prevents exact duplicate Custom Team records
	 * @param teamMemberList
	 * @return void
	 */
    @SuppressWarnings('PMD.ApexCRUDViolation') // Since, Users with Create/Edit (not Delete) on Custom_Teams__c must still change access via a new row
	public static void preventExactDuplicates(List<Custom_Teams__c> teamMemberList) {
		Set<Id> userIds = new Set<Id>();
		Map<String, Custom_Teams__c> newRecordMap = new Map<String, Custom_Teams__c>();
		
		// Collect user IDs and build map of new records
		for (Custom_Teams__c newMember : teamMemberList) {
			if (newMember.Team_Member__c != null && String.isNotBlank(newMember.Related_Record_Id__c)) {
				userIds.add(newMember.Team_Member__c);
				
				String baseKey = String.valueOf(newMember.Team_Member__c) + '_' + newMember.Related_Record_Id__c;
            	newRecordMap.put(baseKey, newMember);
			}
		}
		
		if (userIds.isEmpty()) {
			return;
		}
		
		// Query all existing records for these users
		List<Custom_Teams__c> existingRecords = [
            SELECT Id, Team_Member__c, Access_Level__c, Related_Record_Id__c, Object_API_Name__c
            FROM Custom_Teams__c
            WHERE Team_Member__c IN :userIds
        ];
		
		// List to track records that need to be deleted (for access level changes)
		List<Custom_Teams__c> recordsToDelete = new List<Custom_Teams__c>();
		
		// Check existing records against new ones
		for (Custom_Teams__c existing : existingRecords) {
            if (String.isNotBlank(existing.Related_Record_Id__c)) {
                String baseKey = String.valueOf(existing.Team_Member__c) + '_' + existing.Related_Record_Id__c;
                if (newRecordMap.containsKey(baseKey)) {
                    Custom_Teams__c newMember = newRecordMap.get(baseKey);
                    if (existing.Access_Level__c == newMember.Access_Level__c) {
                        newMember.addError(DUPLICATE_CUSTOM_TEAM + ' ' + 
                                           INFO_MEMBER_ACCESS_START + ' ' + existing.Access_Level__c + 
                                           ' ' + INFO_MEMBER_ACCESS_END);
                    } else {
                        recordsToDelete.add(existing);
                        Nebula.Logger.debug('Marking existing record for deletion (access level change) - ID: ' + existing.Id + 
										', Old Access: ' + existing.Access_Level__c + 
										', New Access: ' + newMember.Access_Level__c).
                            addTag('CustomTeamAutoShareController.preventExactDuplicates');
                        Nebula.Logger.saveLog();
                    }
                    break;
                }
            }
        }
		
		// Delete existing records with different access levels
		if (!recordsToDelete.isEmpty()) {
			try {
				Database.delete(recordsToDelete, false, AccessLevel.SYSTEM_MODE);
                Nebula.Logger.debug('Successfully deleted ' + recordsToDelete.size() + ' existing Custom Team records for access level changes').
                    addTag('CustomTeamAutoShareController.preventExactDuplicates');
				Nebula.Logger.saveLog();
			} catch (DmlException e) {
                Nebula.Logger.error('Error deleting existing Custom Team records: ' + e.getMessage()).
                    addTag('CustomTeamAutoShareController.preventExactDuplicates');
				Nebula.Logger.saveLog();
				throw e;
			}
		}
	}

    /**
     * Helper for after insert trigger methods
     * @param teamMemberList
     * @return void
     */
	public static void handleAfterInsert(List<Custom_Teams__c> teamMemberList) {
		processShares(teamMemberList, true);
	}

	/**
	 * Handles team member updates by processing only records with relevant changes
	 * @param newTeamMembers, oldTeamMemberMap
	 * @return void
	 */
	public static void handleTeamMemberUpdate(List<Custom_Teams__c> newTeamMembers, Map<Id, SObject> oldTeamMemberMap) {
		List<Custom_Teams__c> changedRecords = new List<Custom_Teams__c>();
		List<Custom_Teams__c> oldRecords = new List<Custom_Teams__c>();
		
		// Identify records with relevant changes
		for (Custom_Teams__c newMember : newTeamMembers) {
			Custom_Teams__c oldMember = (Custom_Teams__c)oldTeamMemberMap.get(newMember.Id);
			
			if (hasChanges(newMember, oldMember)) {
				changedRecords.add(newMember);
				oldRecords.add(oldMember);
			}
		}
		
		if (!changedRecords.isEmpty()) {
			handleAfterInsert(changedRecords);
		}
	}

    /**
     * Helper for after delete trigger methods
     * @param teamMemberList
     * @return void
     */
	public static void handleAfterDelete(List<Custom_Teams__c> teamMemberList) {
		processShares(teamMemberList, false);
	}

    /**
     * Sets Custom Team OwnerId to the related parent record owner.
     * @param newRecordList Custom Teams being inserted (Trigger.new)
     */
    public static void setOwnerFromRelatedRecord(List<Custom_Teams__c> newRecordList) {
        if (newRecordList == null || newRecordList.isEmpty()) {
            return;
        }

        Map<String, Set<Id>> recordIdsByObject = new Map<String, Set<Id>>();

        for (Custom_Teams__c team : newRecordList) {
            if (String.isNotBlank(team.Object_API_Name__c) && String.isNotBlank(team.Related_Record_Id__c)) {
                String objectName = team.Object_API_Name__c;
                if (!recordIdsByObject.containsKey(objectName)) {
                    recordIdsByObject.put(objectName, new Set<Id>());
                }
                try {
                    recordIdsByObject.get(objectName).add(Id.valueOf(team.Related_Record_Id__c));
                } catch (Exception ex) {
                    continue;
                }
            }
        }

        Map<Id, Id> recordIdToOwnerId = new Map<Id, Id>();
        for (String objectName : recordIdsByObject.keySet()) {
            Set<Id> recordIds = recordIdsByObject.get(objectName);
            if (recordIds == null || recordIds.isEmpty()) {
                continue;
            }
            recordIdToOwnerId.putAll(queryOwnersByObjectType(objectName, new List<Id>(recordIds)));
        }

        for (Custom_Teams__c team : newRecordList) {
            if (String.isBlank(team.Related_Record_Id__c)) {
                continue;
            }
            try {
                Id recordId = Id.valueOf(team.Related_Record_Id__c);
                if (recordIdToOwnerId.containsKey(recordId)) {
                    team.OwnerId = recordIdToOwnerId.get(recordId);
                }
            } catch (Exception ex) {
                continue;
            }
        }
    }

	/**
	 * US-55796: Handles owner changes on parent objects by cleaning up related Custom Teams
	 * @param records List of parent records with owner changes
	 * @param oldMap Map of old record values
	 */
    @SuppressWarnings('PMD.ApexCRUDViolation')
	public static void handleOwnerChange(List<SObject> records, Map<Id,SObject> oldMap) {
        if(records == null || records.isEmpty() || oldMap == null || oldMap.isEmpty()) {
            Nebula.Logger.debug('Exiting early - null or empty parameters').
                addTag('CustomTeamAutoShareController.handleOwnerChange');
            Nebula.Logger.saveLog();
            return;
        }
        
        try {
            // Determine the SObject Type of the records being processed
            String parentObjectName = records[0].getSObjectType().getDescribe().getName();
            
            // Collect records with owner changes
            Set<Id> changedRecordIds = new Set<Id>();
            for(SObject rec : records) {
                SObject oldRec = oldMap.get(rec.Id);
                // Check for OwnerId change
                if(oldRec != null && rec.get('OwnerId') != oldRec.get('OwnerId')){
                    changedRecordIds.add(rec.Id);
                }
            }
            
            if(changedRecordIds.isEmpty()) {
                return;
            }
            
            List<Custom_Teams__c> teamsToDelete = [
                SELECT Id, Team_Member__c, Related_Record_Id__c, Object_API_Name__c
                FROM Custom_Teams__c
                WHERE Related_Record_Id__c IN :changedRecordIds
                AND Object_API_Name__c = :parentObjectName
            ];
            
            // Delete records if found
            if(!teamsToDelete.isEmpty()) {
                Nebula.Logger.debug('Deleting ' + teamsToDelete.size() + ' Custom Teams records due to owner changes').
                    addTag('CustomTeamAutoShareController.handleOwnerChange');
                Nebula.Logger.saveLog();
                Database.delete(teamsToDelete, false, AccessLevel.SYSTEM_MODE);
            }
        } catch (Exception e) {
            Nebula.Logger.error('Error in CustomTeamAutoShareController.handleOwnerChange: ' + e.getMessage()).
                addTag('CustomTeamAutoShareController.handleOwnerChange');
            Nebula.Logger.saveLog();
            throw e;
        }
    }
	
	/**
	 * Get cached object name from record ID to avoid repeated describe calls
	 * @param recordId
	 * @return String
	 */
	private static String getCachedObjectName(Id recordId) {
		String cacheKey = String.valueOf(recordId).substring(0, 3);
		if (!objectNameCache.containsKey(cacheKey)) {
			objectNameCache.put(cacheKey, recordId.getSObjectType().getDescribe().getName());
		}
		return objectNameCache.get(cacheKey);
    }
	
	/**
	 * Checks if a team member record has relevant changes
	 * @param newMember, oldMember
	 * @return Boolean
	 */
	private static Boolean hasChanges(Custom_Teams__c newMember, Custom_Teams__c oldMember) {
		if (newMember.Access_Level__c != oldMember.Access_Level__c || 
            newMember.Team_Member__c != oldMember.Team_Member__c || 
            newMember.Related_Record_Id__c != oldMember.Related_Record_Id__c ||
            newMember.Object_API_Name__c != oldMember.Object_API_Name__c) {
			return true;
		}
		
		return false;
	}
	
	/**
	 * Processes shares for team members (create or delete)
	 * @param teamMemberList, isCreate
	 * @return void
	 */
	private static void processShares(List<Custom_Teams__c> teamMemberList, Boolean isCreate) {
        if (teamMemberList.isEmpty()) {
            return;
        }
    
        // Collect share requests
        List<Map<String, Object>> shareRequests = new List<Map<String, Object>>();

        // For deletes
        Map<String, List<Map<String, Id>>> deleteMap = new Map<String, List<Map<String, Id>>>();
        
        // Cache object names and share object names by actual object name
        Map<String, String> objectToShareObjectMap = new Map<String, String>();

        for (Custom_Teams__c ctm : teamMemberList) {
            if (ctm.Team_Member__c == null || String.isBlank(ctm.Related_Record_Id__c)) {
                continue;
            }
            
            Id relatedRecordId = Id.valueOf(ctm.Related_Record_Id__c);

            String objectName = String.isNotBlank(ctm.Object_API_Name__c) 
                ? ctm.Object_API_Name__c 
                : getCachedObjectName(relatedRecordId);
            
            if (isCreate) {
                // Build request for bulk insert
                shareRequests.add(new Map<String, Object>{
                    'recordId' => relatedRecordId,
                    'userIdOrGroupId' => ctm.Team_Member__c,
                    'accessLevel' => ctm.Access_Level__c
                    });
            } else {
                String shareObjectName = objectToShareObjectMap.get(objectName);
                        
                // Cache the share object name if not already cached
                if (shareObjectName == null) {
                    shareObjectName = GeneralManualSharing.getShareObjectName(objectName);
                    objectToShareObjectMap.put(objectName, shareObjectName);
                }
                
                if (!deleteMap.containsKey(shareObjectName)) {
                    deleteMap.put(shareObjectName, new List<Map<String, Id>>());
                }
                
                deleteMap.get(shareObjectName).add(
                    new Map<String, Id>{
                        'recordId' => relatedRecordId,
                        'userId' => ctm.Team_Member__c
                        }
                );
            }
        }
        
        // Perform bulk create
        if (isCreate && !shareRequests.isEmpty()) {
            List<GeneralManualSharing.SharingResult> results = GeneralManualSharing.createManualShares(shareRequests);
            Nebula.Logger.debug('Share create results = ' + results).
                addTag('CustomTeamAutoShareController.processShares');
            Nebula.Logger.saveLog();
        }
        
        // Perform bulk delete
        if (!isCreate && !deleteMap.isEmpty()) {
            GeneralManualSharing.deleteManualShares(deleteMap);
        }
    }
}