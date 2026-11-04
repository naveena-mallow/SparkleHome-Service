trigger CleanerSharingTrigger on Cleaner__c (after insert, after update) {
    CleanerSharing.sync(Trigger.new, Trigger.oldMap);
}
