public with sharing class BookingController {
    private static final Integer TRAVEL_GAP_MINUTES = 30;
    private static final Integer TIMELINE_MINUTES = 12 * 60;
    private static final String IST_TIME_ZONE = 'Asia/Kolkata';
    private static final Set<String> SCHEDULED_STATUSES = new Set<String>{
        'Confirmed',
        'In Progress'
    };
    private static final Set<String> TIMELINE_STATUSES = new Set<String>{
        'Confirmed',
        'In Progress',
        'Completed'
    };

    public class CleanerTimelineOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Integer jobsToday;
        @AuraEnabled public Decimal hoursToday;
        @AuraEnabled public String capacityText;
        @AuraEnabled public List<JobBlock> jobs;
    }

    public class JobBlock {
        @AuraEnabled public Id bookingId;
        @AuraEnabled public String bookingName;
        @AuraEnabled public String status;
        @AuraEnabled public Integer startOffsetMinutes;
        @AuraEnabled public Integer endOffsetMinutes;
    }

    @AuraEnabled(cacheable=true)
    public static List<CleanerTimelineOption> getCleanerTimeline(Id bookingId) {
        Booking__c booking = getBooking(bookingId, false);
        validateBookingTime(booking);

        Date bookingDay = getIstDate(booking.Start_Time__c);
        Datetime dayStart = getIstDayStart(bookingDay);
        Datetime dayEnd = dayStart.addDays(1);
        Datetime timelineStart = dayStart.addHours(8);
        Datetime timelineEnd = dayStart.addHours(20);
        List<Cleaner__c> cleaners = [
            SELECT Id, Name
            FROM Cleaner__c
            WHERE Cleaner_status__c = 'Active'
            ORDER BY Name
        ];

        if (cleaners.isEmpty()) {
            return new List<CleanerTimelineOption>();
        }

        Set<Id> cleanerIds = new Map<Id, Cleaner__c>(cleaners).keySet();
        Datetime conflictStart = booking.Start_Time__c.addMinutes(-TRAVEL_GAP_MINUTES);
        Datetime conflictEnd = booking.End_Time__c.addMinutes(TRAVEL_GAP_MINUTES);
        List<Booking__c> jobs = [
            SELECT Id, Name, Cleaner__c, Start_Time__c, End_Time__c, Duration_hours__c, Status__c
            FROM Booking__c
            WHERE Cleaner__c IN :cleanerIds
                AND Status__c IN :TIMELINE_STATUSES
                AND (
                    (
                        Start_Time__c < :dayEnd
                        AND (End_Time__c = null OR End_Time__c > :dayStart)
                    )
                    OR (
                        Start_Time__c < :conflictEnd
                        AND (End_Time__c = null OR End_Time__c > :conflictStart)
                    )
                )
            ORDER BY Start_Time__c
        ];
        Map<Id, List<Booking__c>> jobsByCleaner = new Map<Id, List<Booking__c>>();
        for (Booking__c job : jobs) {
            if (!jobsByCleaner.containsKey(job.Cleaner__c)) {
                jobsByCleaner.put(job.Cleaner__c, new List<Booking__c>());
            }
            jobsByCleaner.get(job.Cleaner__c).add(job);
        }

        List<CleanerTimelineOption> result = new List<CleanerTimelineOption>();
        for (Cleaner__c cleaner : cleaners) {
            List<Booking__c> cleanerJobs = jobsByCleaner.containsKey(cleaner.Id)
                ? jobsByCleaner.get(cleaner.Id)
                : new List<Booking__c>();
            if (!isAvailable(cleanerJobs, booking)) {
                continue;
            }

            CleanerTimelineOption row = new CleanerTimelineOption();
            row.id = cleaner.Id;
            row.name = cleaner.Name;
            row.jobsToday = 0;
            row.hoursToday = 0;
            row.jobs = new List<JobBlock>();

            for (Booking__c job : cleanerJobs) {
                if (job.Id == booking.Id || job.Start_Time__c == null) {
                    continue;
                }

                if (job.Start_Time__c >= dayStart && job.Start_Time__c < dayEnd) {
                    row.jobsToday++;
                    if (job.Duration_hours__c != null) {
                        row.hoursToday += job.Duration_hours__c;
                    }
                }

                if (job.Start_Time__c >= timelineEnd
                    || (job.End_Time__c != null && job.End_Time__c <= timelineStart)) {
                    continue;
                }

                JobBlock block = new JobBlock();
                block.bookingId = job.Id;
                block.bookingName = job.Name;
                block.status = job.Status__c;
                block.startOffsetMinutes = Integer.valueOf(String.valueOf(
                    (job.Start_Time__c.getTime() - timelineStart.getTime()) / 60000
                ));
                block.endOffsetMinutes = job.End_Time__c == null
                    ? TIMELINE_MINUTES
                    : Integer.valueOf(String.valueOf(
                        (job.End_Time__c.getTime() - timelineStart.getTime()) / 60000
                    ));
                row.jobs.add(block);
            }

            Integer totalMinutes = (row.hoursToday * 60).intValue();
            Integer wholeHours = totalMinutes / 60;
            Integer remainingMinutes = Math.mod(totalMinutes, 60);
            row.capacityText = wholeHours + 'h ' + String.valueOf(remainingMinutes).leftPad(2, '0') + 'm';
            result.add(row);
        }
        return result;
    }

    @AuraEnabled
    public static void assign(Id bookingId, Id cleanerId) {
        if (cleanerId == null) {
            throw new AuraHandledException('Select a cleaner before assigning the booking.');
        }
        Booking__c booking = getBooking(bookingId, true);
        validateBookingTime(booking);
        if (booking.Status__c != 'Requested') {
            throw new AuraHandledException('Only requested bookings can be assigned.');
        }

        List<Cleaner__c> cleaners = [
            SELECT Id
            FROM Cleaner__c
            WHERE Id = :cleanerId AND Cleaner_status__c = 'Active'
            LIMIT 1
            FOR UPDATE
        ];
        if (cleaners.isEmpty()) {
            throw new AuraHandledException('This cleaner is no longer active.');
        }

        Date bookingDay = getIstDate(booking.Start_Time__c);
        Datetime dayStart = getIstDayStart(bookingDay);
        Datetime dayEnd = dayStart.addDays(1);
        Datetime conflictStart = booking.Start_Time__c.addMinutes(-TRAVEL_GAP_MINUTES);
        Datetime conflictEnd = booking.End_Time__c.addMinutes(TRAVEL_GAP_MINUTES);
        List<Booking__c> cleanerJobs = [
            SELECT Id, Start_Time__c, End_Time__c, Status__c
            FROM Booking__c
            WHERE Cleaner__c = :cleanerId
                AND Status__c IN :TIMELINE_STATUSES
                AND Id != :booking.Id
                AND (
                    (Start_Time__c >= :dayStart AND Start_Time__c < :dayEnd)
                    OR (
                        Start_Time__c < :conflictEnd
                        AND (End_Time__c = null OR End_Time__c > :conflictStart)
                    )
                )
        ];
        if (!isAvailable(cleanerJobs, booking)) {
            throw new AuraHandledException(
                'This cleaner is no longer available for the booking time. Refresh the list and choose another cleaner.'
            );
        }

        update new Booking__c(
            Id = booking.Id,
            Cleaner__c = cleanerId,
            Status__c = 'Confirmed'
        );
    }

    private static Booking__c getBooking(Id bookingId, Boolean lockRecord) {
        if (bookingId == null) {
            throw new AuraHandledException('A booking is required.');
        }
        List<Booking__c> bookings;
        if (lockRecord) {
            bookings = [
                SELECT Id, Start_Time__c, End_Time__c, Status__c
                FROM Booking__c
                WHERE Id = :bookingId
                LIMIT 1
                FOR UPDATE
            ];
        } else {
            bookings = [
                SELECT Id, Start_Time__c, End_Time__c, Status__c
                FROM Booking__c
                WHERE Id = :bookingId
                LIMIT 1
            ];
        }
        if (bookings.isEmpty()) {
            throw new AuraHandledException('The requested booking could not be found.');
        }
        return bookings[0];
    }

    private static void validateBookingTime(Booking__c booking) {
        if (booking.Start_Time__c == null || booking.End_Time__c == null
            || booking.End_Time__c <= booking.Start_Time__c) {
            throw new AuraHandledException('The booking must have a valid start and end time before assigning a cleaner.');
        }
    }

    private static Boolean isAvailable(List<Booking__c> jobs, Booking__c booking) {
        Datetime conflictStart = booking.Start_Time__c.addMinutes(-TRAVEL_GAP_MINUTES);
        Datetime conflictEnd = booking.End_Time__c.addMinutes(TRAVEL_GAP_MINUTES);
        for (Booking__c job : jobs) {
            if (job.Id == booking.Id || job.Start_Time__c == null
                || !SCHEDULED_STATUSES.contains(job.Status__c)) {
                continue;
            }
            if (job.End_Time__c == null
                || (job.Start_Time__c < conflictEnd && job.End_Time__c > conflictStart)) {
                return false;
            }
        }
        return true;
    }

    private static Date getIstDate(Datetime value) {
        return Date.valueOf(value.format('yyyy-MM-dd', IST_TIME_ZONE));
    }

    private static Datetime getIstDayStart(Date day) {
        return Datetime.newInstanceGmt(day, Time.newInstance(0, 0, 0, 0)).addMinutes(-330);
    }

}
