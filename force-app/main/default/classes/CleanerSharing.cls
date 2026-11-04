public without sharing class CleanerSharing {
    public static void sync(List<Cleaner__c> newCleaners, Map<Id, Cleaner__c> oldMap) {
        Set<Id> changedCleanerIds = new Set<Id>();
        List<Cleaner__Share> sharesToInsert = new List<Cleaner__Share>();

        for (Cleaner__c cleaner : newCleaners) {
            Cleaner__c oldCleaner = oldMap == null ? null : oldMap.get(cleaner.Id);
            if (oldCleaner != null && oldCleaner.User__c == cleaner.User__c) {
                continue;
            }

            changedCleanerIds.add(cleaner.Id);
            if (cleaner.User__c == null) {
                continue;
            }

            Cleaner__Share shareRow = new Cleaner__Share();
            shareRow.ParentId = cleaner.Id;
            shareRow.UserOrGroupId = cleaner.User__c;
            shareRow.AccessLevel = 'Read';
            shareRow.RowCause = Schema.Cleaner__Share.RowCause.Assigned_Cleaner_User__c;
            sharesToInsert.add(shareRow);
        }

        if (changedCleanerIds.isEmpty()) {
            return;
        }

        List<Cleaner__Share> oldShares = [
            SELECT Id
            FROM Cleaner__Share
            WHERE ParentId IN :changedCleanerIds
                AND RowCause = 'Assigned_Cleaner_User__c'
        ];
        if (!oldShares.isEmpty()) {
            delete oldShares;
        }
        if (!sharesToInsert.isEmpty()) {
            Database.SaveResult[] results = Database.insert(sharesToInsert, false);
            Map<Id, Cleaner__c> cleanersById = new Map<Id, Cleaner__c>(newCleaners);
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    continue;
                }
                for (Database.Error error : results[i].getErrors()) {
                    if (error.getStatusCode() == StatusCode.FIELD_INTEGRITY_EXCEPTION
                        && error.getMessage().contains('trivial share level')) {
                        continue;
                    }
                    cleanersById.get(sharesToInsert[i].ParentId).addError(
                        'Unable to share this cleaner record: ' + error.getMessage()
                    );
                }
            }
        }
    }
}
