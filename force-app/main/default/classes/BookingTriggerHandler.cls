public without sharing class BookingTriggerHandler {
private static final String IST_TIME_ZONE = 'Asia/Kolkata';

private static Tax_Config__mdt getConfig() {
    return Tax_Config__mdt.getInstance('Default_GST');
}

private static Integer getMinimumNoticeHours() {
    return Integer.valueOf(getConfig().Minimum_Notice_Hours__c);
}

private static Integer getTravelGapMinutes() {
    return Integer.valueOf(getConfig().Travel_Gap_Minutes__c);
}

private static Integer getBusinessStartHour() {
    return Integer.valueOf(getConfig().Business_Start_Hour__c);
}

private static Integer getBusinessEndHour() {
    return Integer.valueOf(getConfig().Business_End_Hour__c);
}
    private static final Set<String> SCHEDULED_STATUSES = new Set<String>{
        'Confirmed',
        'In Progress'
    };

    public static void beforeInsert(List<Booking__c> newBookings) {
        validateBookings(newBookings, null);
    }

    public static void beforeUpdate(
        List<Booking__c> newBookings,
        Map<Id, Booking__c> oldMap
    ) {
        validateBookings(newBookings, oldMap);
    }

    private static void validateBookings(
        List<Booking__c> bookings,
        Map<Id, Booking__c> oldMap
    ) {
        Set<Id> cleanerIds = new Set<Id>();
        Set<Id> scheduledCleanerIds = new Set<Id>();
        Datetime earliestStart;
        Datetime latestEnd;

        for (Booking__c booking : bookings) {
            Booking__c oldBooking = oldMap == null ? null : oldMap.get(booking.Id);
            Boolean scheduleChanged = oldBooking == null
                || oldBooking.Start_Time__c != booking.Start_Time__c
                || oldBooking.End_Time__c != booking.End_Time__c;

            if (booking.Start_Time__c == null) {
                booking.addError('A booking start time is required.');
                continue;
            }

if (scheduleChanged &&
    booking.Start_Time__c < System.now().addHours(getMinimumNoticeHours())) {

    booking.Start_Time__c.addError(
        'Bookings must be scheduled at least '
        + getMinimumNoticeHours()
        + ' hours in advance.'
    );
}
            

            if (booking.Cleaner__c != null) {
                cleanerIds.add(booking.Cleaner__c);
            }

            if (booking.End_Time__c == null || booking.End_Time__c <= booking.Start_Time__c) {
                continue;
            }

            Date startDay = Date.valueOf(booking.Start_Time__c.format('yyyy-MM-dd', IST_TIME_ZONE));
            Date endDay = Date.valueOf(booking.End_Time__c.format('yyyy-MM-dd', IST_TIME_ZONE));
            Integer startHour = Integer.valueOf(booking.Start_Time__c.format('HH', IST_TIME_ZONE));
            Integer endHour = Integer.valueOf(booking.End_Time__c.format('HH', IST_TIME_ZONE));
            Integer endMinute = Integer.valueOf(booking.End_Time__c.format('mm', IST_TIME_ZONE));
            Integer endSecond = Integer.valueOf(booking.End_Time__c.format('ss', IST_TIME_ZONE));
            Integer businessStartHour = getBusinessStartHour();
Integer businessEndHour = getBusinessEndHour();

if (startDay != endDay
    || startHour < businessStartHour
    || endHour > businessEndHour
    || (endHour == businessEndHour &&
        (endMinute > 0 || endSecond > 0))) {

    booking.addError(
        'Bookings must start at or after '
        + businessStartHour
        + ':00 and end by '
        + businessEndHour
        + ':00 India time on the same day.'
    );
}

            if (booking.Cleaner__c != null) {
                scheduledCleanerIds.add(booking.Cleaner__c);
                Integer travelGap = getTravelGapMinutes();

Datetime bufferedStart =
    booking.Start_Time__c.addMinutes(-travelGap);

Datetime bufferedEnd =
    booking.End_Time__c.addMinutes(travelGap);
                if (earliestStart == null || bufferedStart < earliestStart) {
                    earliestStart = bufferedStart;
                }
                if (latestEnd == null || bufferedEnd > latestEnd) {
                    latestEnd = bufferedEnd;
                }
            }
        }

        if (cleanerIds.isEmpty()) {
            return;
        }

        Map<Id, Cleaner__c> cleanersById = new Map<Id, Cleaner__c>([
            SELECT Id, Cleaner_status__c
            FROM Cleaner__c
            WHERE Id IN :cleanerIds
        ]);
        /*
        for (Booking__c booking : bookings) {
            if (booking.Cleaner__c != null
                && (!cleanersById.containsKey(booking.Cleaner__c)
                    || cleanersById.get(booking.Cleaner__c).Cleaner_status__c != 'Active')) {
                booking.Cleaner__c.addError('Bookings can only be assigned to active cleaners.');
            }
        }
        */

        if (scheduledCleanerIds.isEmpty()) {
            return;
        }

        List<Booking__c> existingJobs = [
            SELECT Id, Cleaner__c, Start_Time__c, End_Time__c, Status__c
            FROM Booking__c
            WHERE Cleaner__c IN :scheduledCleanerIds
                AND Status__c IN :SCHEDULED_STATUSES
                AND Start_Time__c < :latestEnd
                AND (End_Time__c = null OR End_Time__c > :earliestStart)
        ];

        for (Integer bookingIndex = 0; bookingIndex < bookings.size(); bookingIndex++) {
            Booking__c booking = bookings[bookingIndex];
            if (booking.Cleaner__c == null || booking.Start_Time__c == null
                || booking.End_Time__c == null || !SCHEDULED_STATUSES.contains(booking.Status__c)) {
                continue;
            }

            for (Booking__c existingJob : existingJobs) {
                if (existingJob.Id == booking.Id
                    || existingJob.Cleaner__c != booking.Cleaner__c
                    || existingJob.Start_Time__c == null) {
                    continue;
                }
                if (conflicts(booking.Start_Time__c, booking.End_Time__c,
                    existingJob.Start_Time__c, existingJob.End_Time__c)) {
                    booking.addError('The cleaner already has a booking within the required 30-minute travel gap.');
                    break;
                }
            }

            for (Integer otherIndex = bookingIndex + 1; otherIndex < bookings.size(); otherIndex++) {
                Booking__c otherBooking = bookings[otherIndex];
                if (otherBooking.Cleaner__c != booking.Cleaner__c
                    || otherBooking.Start_Time__c == null || otherBooking.End_Time__c == null
                    || !SCHEDULED_STATUSES.contains(otherBooking.Status__c)) {
                    continue;
                }
                if (conflicts(booking.Start_Time__c, booking.End_Time__c,
                    otherBooking.Start_Time__c, otherBooking.End_Time__c)) {
                    booking.addError('This import contains another booking for the cleaner within the required 30-minute travel gap.');
                    otherBooking.addError('This import contains another booking for the cleaner within the required 30-minute travel gap.');
                }
            }
        }
    }

    private static Boolean conflicts(
    Datetime firstStart,
    Datetime firstEnd,
    Datetime secondStart,
    Datetime secondEnd
) {
    Integer travelGap = getTravelGapMinutes();

    return secondEnd == null
        || (firstStart < secondEnd.addMinutes(travelGap)
            && firstEnd.addMinutes(travelGap) > secondStart);
}
}