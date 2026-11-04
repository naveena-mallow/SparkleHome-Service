public without sharing class BookingSharing {
    public static void sync(
        List<Booking__c> newList,
        Map<Id, Booking__c> oldMap
    ) {
        Set<Id> cleanerIds = new Set<Id>();
        Set<Id> bookingIdsToClean = new Set<Id>();

        for (Booking__c booking : newList) {
            Booking__c oldBooking = oldMap == null ? null : oldMap.get(booking.Id);
            if (oldBooking == null
                || oldBooking.Cleaner__c != booking.Cleaner__c
                || oldBooking.OwnerId != booking.OwnerId) {
                bookingIdsToClean.add(booking.Id);
                if (oldBooking != null && oldBooking.Cleaner__c != null) {
                    cleanerIds.add(oldBooking.Cleaner__c);
                }
                if (booking.Cleaner__c != null) {
                    cleanerIds.add(booking.Cleaner__c);
                }
            }
        }
        if (bookingIdsToClean.isEmpty()) {
            return;
        }

        Set<Id> cleanerUserIds = new Set<Id>();
        Map<Id, Cleaner__c> cleanersById = cleanerIds.isEmpty()
            ? new Map<Id, Cleaner__c>()
            : new Map<Id, Cleaner__c>([
                SELECT Id, User__c
                FROM Cleaner__c
                WHERE Id IN :cleanerIds
            ]);
        for (Cleaner__c cleaner : cleanersById.values()) {
            if (cleaner.User__c != null) {
                cleanerUserIds.add(cleaner.User__c);
            }
        }

        List<Booking__Share> sharesToInsert = new List<Booking__Share>();
        for (Booking__c booking : newList) {
            Booking__c oldBooking = oldMap == null ? null : oldMap.get(booking.Id);
            if (oldBooking != null
                && oldBooking.Cleaner__c == booking.Cleaner__c
                && oldBooking.OwnerId == booking.OwnerId) {
                continue;
            }
            if (booking.Cleaner__c == null || !cleanersById.containsKey(booking.Cleaner__c)) {
                continue;
            }
            Id cleanerUserId = cleanersById.get(booking.Cleaner__c).User__c;
            if (cleanerUserId == null) {
                continue;
            }

            Booking__Share shareRow = new Booking__Share();
            shareRow.ParentId = booking.Id;
            shareRow.UserOrGroupId = cleanerUserId;
            shareRow.AccessLevel = 'Edit';
            shareRow.RowCause = Schema.Booking__Share.RowCause.Manual;
            sharesToInsert.add(shareRow);
        }

        List<Booking__Share> oldShares = [
            SELECT Id
            FROM Booking__Share
            WHERE ParentId IN :bookingIdsToClean
                AND (
                    RowCause = 'Assigned_Cleaner__c'
                    OR (RowCause = 'Manual' AND UserOrGroupId IN :cleanerUserIds)
                )
        ];
        if (!oldShares.isEmpty()) {
            delete oldShares;
        }
        if (!sharesToInsert.isEmpty()) {
            insert sharesToInsert;
        }
    }
}
