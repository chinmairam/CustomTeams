import { LightningElement, wire, api, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { getPicklistValues } from 'lightning/uiObjectInfoApi'; 
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTeamMembers from '@salesforce/apex/CustomTeamRelatedListController.getTeamMembers';
import deleteTeamMembers from '@salesforce/apex/CustomTeamRelatedListController.deleteTeamMembers';
import sendNotifications from '@salesforce/apex/CustomTeamRelatedListController.sendNotifications';
import CUSTOM_TEAMS_OBJECT from '@salesforce/schema/Custom_Teams__c';
import TEAM_MEMBER_FIELD from '@salesforce/schema/Custom_Teams__c.Team_Member__c';
import ACCESS_LEVEL_FIELD from '@salesforce/schema/Custom_Teams__c.Access_Level__c';
import TEAM_ROLE_FIELD from '@salesforce/schema/Custom_Teams__c.Team_Role__c';
import OWNER_FIELD from '@salesforce/schema/Custom_Teams__c.OwnerId';
import NO_TEAM_MEMBERS_MSG from '@salesforce/label/c.NO_TEAM_MEMBERS';
import NEW_CUSTOM_TEAM from '@salesforce/label/c.NEW_CUSTOM_TEAM';
import EDIT_CUSTOM_TEAM from '@salesforce/label/c.EDIT_CUSTOM_TEAM';
import TEAMMEMBER from '@salesforce/label/c.TEAM_MEMBER';
import ACCESSLEVEL from '@salesforce/label/c.ACCESS_LEVEL';
import TEAMROLE from '@salesforce/label/c.TEAM_ROLE';
import ERROR_LOADING_MEMBERS from '@salesforce/label/c.ERROR_LOADING_MEMBERS';
import ERROR_FETCHING_OBJ_INFO from '@salesforce/label/c.ERROR_FETCHING_OBJ_INFO';
import ERROR_FETCHING_ACCESS_LEVELS from '@salesforce/label/c.ERROR_FETCHING_ACCESS_LEVELS';
import ERROR_FETCHING_TEAM_ROLES from '@salesforce/label/c.ERROR_FETCHING_TEAM_ROLES';
import MEMBER_DELETE_PROMPT from '@salesforce/label/c.TEAM_MEMBER_DELETE_PROMPT';
import MEMBER_DELETE_SUCCESS from '@salesforce/label/c.TEAM_MEMBER_DELETE_SUCCESS';
import ERROR_MEMBER_DELETE from '@salesforce/label/c.ERROR_TEAM_MEMBER_DELETE';
import TITLE from '@salesforce/label/c.CUSTOM_TEAMS';
import MEMBER_ADDED_SUCCESS from '@salesforce/label/c.TEAM_MEMBER_ADDED_SUCCESS';
import MEMBER_UPDATE_SUCCESS from '@salesforce/label/c.TEAM_MEMBER_UPDATE_SUCCESS';
import ERROR_ADDING_MEBER from '@salesforce/label/c.ERROR_ADDING_TEAM_MEBER';
import ERROR_EDITING_MEMBER from '@salesforce/label/c.ERROR_EDITING_TEAM_MEMBER';

const FIELD_COLUMNS = [
    { 
        label: TEAMMEMBER,
        fieldName: 'teamMemberUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'teamMemberName' }, target: '_blank' },
        sortable: true,
        wrapText: true
    },
    { label: ACCESSLEVEL, fieldName: 'accessLevel', type: 'text', sortable: true, wrapText: true },
    { label: TEAMROLE, fieldName: 'teamRole', type: 'text', sortable: true, wrapText: true }
];

export default class CustomRelatedList extends LightningElement {
    @api recordId;
    @api objectApiName;
    
    @track teamMembers = [];
    @track columns = [];
    @track isLoading = false;
    @track showAddModal = false;
    @track showEditModal = false;
    @track accessLevelOptions = [];
    @track teamRoleOptions = [];
    @track editingTeamId;
    @track canEdit = false;
    @track canDelete = false;
    sortedBy;
    defaultSortDirection = 'asc';
    sortDirection = 'asc';

    customTeamObject = CUSTOM_TEAMS_OBJECT;
    teamMemberField = TEAM_MEMBER_FIELD;
    accessLevelField = ACCESS_LEVEL_FIELD;
    teamRoleField = TEAM_ROLE_FIELD;
    ownerField = OWNER_FIELD;

    labels = {
        NO_TEAM_MEMBERS_MSG,
        NEW_CUSTOM_TEAM,
        EDIT_CUSTOM_TEAM
    }

    teamMembersResult;

    get nameField() {
        return `${this.objectApiName}.Name`;
    }

    get parentOwnerIdField() {
        return `${this.objectApiName}.OwnerId`;
    }

    get parentOwnerNameField() {
        return `${this.objectApiName}.Owner.Name`;
    }

    get parentFields() {
        if (!this.objectApiName) {
            return undefined;
        }
        return [this.nameField, this.parentOwnerIdField, this.parentOwnerNameField];
    }

    @wire(getRecord, { recordId: '$recordId', fields: '$parentFields' })
    parentRecord;

    get currentRecordName() {
        const name = getFieldValue(this.parentRecord.data, this.nameField);
        return name ? name : '';
    }

    get parentOwnerId() {
        return getFieldValue(this.parentRecord.data, this.parentOwnerIdField);
    }

    get parentOwnerName() {
        return getFieldValue(this.parentRecord.data, this.parentOwnerNameField) || '';
    }

    @wire(getTeamMembers, { recordId: '$recordId' })
    wiredTeamMembers(result) {
        this.teamMembersResult = result;
        if (result.data) {
            this.teamMembers = result.data.map(row => {
            return {
                ...row,
                teamMemberUrl: `/${row.teamMemberId}` 
            };
        });
        } else if (result.error) {
            this.showToast('Error', ERROR_LOADING_MEMBERS, result.error);
            const logger = this?.template?.querySelector("nebula-logger");
            logger
                .error(result.error?.body?.message, error)
                .addTag("customTeamsRelatedList")
                .setRecordId(this.recordId);
            logger.saveLog();
        }
    }

    teamInfo;

    @wire(getObjectInfo, { objectApiName: CUSTOM_TEAMS_OBJECT })
    wiredTeamInfo(result) {
        this.teamInfo = result;
        if (result.data) {
            // Check if user has edit permission
            this.canEdit = result.data.updateable;

            // Check if user has delete permission
            this.canDelete = result.data.deletable;
            
            // Build columns based on permissions
            this.buildColumns();
        } else if (result.error) {
            this.showToast('Error', ERROR_FETCHING_OBJ_INFO, result.error);
            const logger = this?.template?.querySelector("nebula-logger");
            logger
                .error(error?.body?.message, error)
                .addTag("customTeamsRelatedList")
                .setRecordId(this.recordId);
            logger.saveLog();
        }
    }

    @wire(getPicklistValues, { 
     recordTypeId: '$teamInfo.data.defaultRecordTypeId', fieldApiName: ACCESS_LEVEL_FIELD })     
    wiredAccessLevelValues({ error, data }) {         
        if (data) {             
            this.accessLevelOptions = data.values.map(item => ({
                label: item.label,
                value: item.value
            }));      
        } else if (error) {             
            this.showToast('Error', ERROR_FETCHING_ACCESS_LEVELS, error);
            const logger = this?.template?.querySelector("nebula-logger");
            logger
                .error(error?.body?.message, error)
                .addTag("customTeamsRelatedList")
                .setRecordId(this.recordId);
            logger.saveLog();
        }
    }

    @wire(getPicklistValues, { 
     recordTypeId: '$teamInfo.data.defaultRecordTypeId', fieldApiName: TEAM_ROLE_FIELD })     
    wiredTeamRoleValues({ error, data }) {         
        if (data) {             
            this.teamRoleOptions = data.values.map(item => ({
                label: item.label,
                value: item.value
            }));      
        } else if (error) {             
            this.showToast('Error', ERROR_FETCHING_TEAM_ROLES, error);
            const logger = this?.template?.querySelector("nebula-logger");
            logger
                .error(error?.body?.message, error)
                .addTag("customTeamsRelatedList")
                .setRecordId(this.recordId);
            logger.saveLog();
        }
    }

    onHandleSort(event) {
        this.sortedBy = event.detail.fieldName;
        this.sortDirection = event.detail.sortDirection;
        this.sortData(this.sortedBy, this.sortDirection);
    }
 
    sortData(fieldname, direction) {
        let parseData = JSON.parse(JSON.stringify(this.teamMembers));

        let key = (a) => {
            return a[fieldname];
        };

        let isReverse = direction === 'asc' ? 1: -1;

        parseData.sort((x, y) => {
            x = key(x) ? key(x) : '';
            y = key(y) ? key(y) : '';

            return isReverse * ((x > y) - (y > x));
        });
        this.teamMembers = parseData;
    }

    buildColumns() {
        const rowActions = [];
        if(this.canEdit) {
            rowActions.push({ label: 'Edit', name: 'edit' });
        }
        
        if (this.canDelete) {
            rowActions.push({ label: 'Delete', name: 'delete' });
        }

        this.columns = [
            ...FIELD_COLUMNS,
            {
                type: 'action',
                typeAttributes: { rowActions }
            }
        ];
    }

    handleUserSelect(event) {
        this.selectedUserId = event.currentTarget.dataset.userId;
        const userName = event.currentTarget.dataset.userName;
        this.userSearchTerm = userName;
        this.userSearchResults = [];
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        
        switch (actionName) {
            case 'edit':
                this.handleEdit(row);
                break;
            case 'delete':
                this.handleDelete(row);
                break;
            default:
                break;
        }
    }

    handleAddNew() {
        this.showAddModal = true;
    }

    handleCancelAdd() {
        this.showAddModal = false;
    }

    handleEdit(row) {
        this.editingTeamId = row.id;
        this.showEditModal = true;
    }

    async handleDelete(row) {
        if (!confirm(MEMBER_DELETE_PROMPT)) {
            return;
        }
        
        const deletedMember = row.teamMemberId;
        this.isLoading = true;
        try {
            await deleteTeamMembers({ teamIds: [row.id] });

            this.triggerNotification('Delete', deletedMember, '');
            this.teamMembers = this.teamMembers.filter(member => member.id !== row.id);

            this.showToast('Success', MEMBER_DELETE_SUCCESS, 'success');
            await refreshApex(this.teamMembersResult);
        } catch (error) {
            this.showToast('Error', error.body?.message || ERROR_MEMBER_DELETE, 'error');
            const logger = this?.template?.querySelector("nebula-logger");
            logger
                .error(error?.body?.message, error)
                .addTag("customTeamsRelatedList")
                .setRecordId(this.recordId);
            logger.saveLog();
        } finally {
            this.isLoading = false;
        }
    }

    handleCancelEdit() {
        this.showEditModal = false;
        this.editingTeamId = null;
    }

    get hasTeamMembers() {
        return this.teamMembers && this.teamMembers.length > 0;
    }
    
    get cardTitle() {
        return TITLE + ` (${this.teamMembers.length || 0})`;
    }

    handleSaveAdd(event) {
        event.preventDefault();
        const fields = event.detail.fields;
        
        // Set the Related_Record_Id and Object_API_Name
        fields.Related_Record_Id__c = this.recordId;
        fields.Object_API_Name__c = this.objectApiName;
        if (this.parentOwnerId) {
            fields.OwnerId = this.parentOwnerId;
        }
        
        this.isLoading = true;
        this.template.querySelector('lightning-record-edit-form').submit(fields);
    }

    handleAddSuccess(event) {
        const fields = event.detail.fields;
        const memberId = fields.Team_Member__c.value;

        this.triggerNotification('Insert', memberId, '');

        this.isLoading = false;
        this.showAddModal = false;
        this.showToast('Success', MEMBER_ADDED_SUCCESS, 'success');
        refreshApex(this.teamMembersResult);
    }

    handleEditSuccess(event) {
        const fields = event.detail.fields;
        const memberId = fields.Team_Member__c.value;
        const accessLevel = fields.Access_Level__c.value;

        const oldRecord = this.teamMembers.find(member => member.id === this.editingTeamId);

        if (oldRecord && oldRecord.accessLevel !== accessLevel) {
            this.triggerNotification('Update', memberId, accessLevel);
        }

        this.isLoading = false;
        this.showEditModal = false;
        this.editingTeamId = null;
        this.showToast('Success', MEMBER_UPDATE_SUCCESS, 'success');
        refreshApex(this.teamMembersResult);
    }
    
    handleAddError(event) {
        this.isLoading = false;

        const errorMessage = event.detail?.detail || event.detail?.message || ERROR_ADDING_MEBER;

        this.showToast('Error', errorMessage, 'error');
    }

    handleEditError(event) {
        this.isLoading = false;

        const errorMessage = event.detail?.detail || event.detail?.message || ERROR_EDITING_MEMBER;

        this.showToast('Error', errorMessage, 'error');
    }

    triggerNotification(type, memberId, access) {
        let objectApiName = this.objectApiName;
        let nameValue = '';
        if (this.parentRecord && this.parentRecord.fields) {
            nameValue = getFieldValue(this.parentRecord, { fieldApiName: 'Name', objectApiName: this.objectApiName }) || 
                        this.parentRecord.fields.Name?.value || 
                        '';
        }

        sendNotifications({
            action: type,
            memberId: memberId,
            recordId: this.recordId,
            recordName: this.currentRecordName,
            objectApiName: objectApiName,
            accessLevel: access
        }).catch(
            error => this.showToast('Error', error.body?.message, 'error'
        ));
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }
}