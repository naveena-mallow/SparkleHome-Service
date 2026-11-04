public with sharing class TodaysJobsController {

    @AuraEnabled(cacheable=true)
    public static List<Booking__c> getTodaysJobs() {

        Date todayDate = Date.today();

        Datetime startOfDay =
            Datetime.newInstance(
                todayDate,
                Time.newInstance(0, 0, 0, 0)
            );

        Datetime endOfDay =
            startOfDay.addDays(1);

        return [
            SELECT Id,
                   Name,
                   Service__c,
                   Status__c,
                   Start_Time__c,
                   End_Time__c,
                   Duration_Hours__c,
                   Total__c,
                   Payment_Status__c,
                   Payment_Mode__c,
                   Customer_Name__c,
                   Customer_Phone__c,
                   Customer_Address__c,
                   Cancellation_Reason__c,
                   Cleaner__r.Name
            FROM Booking__c
            WHERE Status__c != 'Cancelled'
            AND Start_Time__c >= :startOfDay
            AND Start_Time__c < :endOfDay
            ORDER BY Start_Time__c ASC
        ];
    }

    @AuraEnabled(cacheable=true)
    public static Booking__c getBooking(Id bookingId) {

        if (bookingId == null) {
            throw new AuraHandledException(
                'Booking Id is required.'
            );
        }

        return [
            SELECT Id,
                   Name,
                   Service__c,
                   Status__c,
                   Start_Time__c,
                   End_Time__c,
                   Duration_Hours__c,
                   Total__c,
                   Payment_Status__c,
                   Payment_Mode__c,
                   Customer_Name__c,
                   Customer_Phone__c,
                   Customer_Address__c,
                   Cancellation_Reason__c,
                   Cleaner__c
            FROM Booking__c
            WHERE Id = :bookingId
            LIMIT 1
        ];
    }

    @AuraEnabled
    public static void startJob(Id bookingId) {

        try {

            if (bookingId == null) {
                throw new AuraHandledException(
                    'Booking Id is required.'
                );
            }

            update new Booking__c(
                Id = bookingId,
                Status__c = 'In Progress'
            );

        } catch (DmlException e) {

            throw new AuraHandledException(
                e.getDmlMessage(0)
            );

        } catch (Exception e) {

            throw new AuraHandledException(
                e.getMessage()
            );
        }
    }

    @AuraEnabled
    public static void completeJob(
        Id bookingId,
        Boolean paid,
        String paymentMode
    ) {

        try {

            if (bookingId == null) {
                throw new AuraHandledException(
                    'Booking Id is required.'
                );
            }

            update new Booking__c(
                Id = bookingId,
                Status__c = 'Completed',
                Payment_Status__c = paid ? 'Paid' : 'Unpaid',
                Payment_Mode__c = paid ? paymentMode : null
            );

        } catch (DmlException e) {

            throw new AuraHandledException(
                e.getDmlMessage(0)
            );

        } catch (Exception e) {

            throw new AuraHandledException(
                e.getMessage()
            );
        }
    }
}