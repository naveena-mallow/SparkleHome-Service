trigger BookingTrigger on Booking__c (
    before insert,
    before update,
    after insert,
    after update
) {
    if (Trigger.isBefore && Trigger.isInsert) {
        BookingTriggerHandler.beforeInsert(Trigger.new);
    }

    if (Trigger.isBefore && Trigger.isUpdate) {
        BookingTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
    }

    if (Trigger.isAfter) {
        BookingSharing.sync(Trigger.new, Trigger.oldMap);
        BookingEmail.sendConfirmations(Trigger.new, Trigger.oldMap);
    }
}
