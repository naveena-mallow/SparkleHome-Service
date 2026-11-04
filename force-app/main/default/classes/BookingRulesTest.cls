@IsTest
private class BookingRulesTest {
    @TestSetup
    static void setup() {
        TestDataFactory.createRateCards();
        TestDataFactory.createCleaner('Lakshmi', true);
        TestDataFactory.createCleaner('Ramesh', true);
        TestDataFactory.createCleaner('Inactive Cleaner', false);
        TestDataFactory.createCustomer('2 BHK');
        TestDataFactory.createCustomer('3 BHK');
    }

    @IsTest
    static void rejectsBookingsInsideFourHourNotice() {
        Customers__c customer = customer('2 BHK');
        Booking__c booking = draftBooking(
            customer.Id,
            null,
            System.now().addHours(2),
            'Requested'
        );

        Database.SaveResult result = Database.insert(booking, false);

        System.assertEquals(false, result.isSuccess());
        Boolean includesNoticeError = false;
        for (Database.Error error : result.getErrors()) {
            if (error.getMessage().contains('4 hours')) {
                includesNoticeError = true;
            }
        }
        System.assert(includesNoticeError, 'Expected the four-hour notice validation.');
    }

    @IsTest
    static void rejectsStartsBeforeEightAmIndiaTime() {
        Customers__c customer = customer('2 BHK');
        Datetime startTime = TestDataFactory.futureBusinessStart(10, 7, 0);

        Database.SaveResult result = Database.insert(
            draftBooking(customer.Id, null, startTime, 'Requested'),
            false
        );

        System.assertEquals(false, result.isSuccess());
        System.assert(result.getErrors()[0].getMessage().contains('8:00 AM'));
    }

    @IsTest
    static void rejectsEndAfterEightPmIndiaTime() {
        Customers__c customer = customer('2 BHK');
        Datetime startTime = TestDataFactory.futureBusinessStart(10, 19, 0);

        Database.SaveResult result = Database.insert(
            draftBooking(customer.Id, null, startTime, 'Requested'),
            false
        );

        System.assertEquals(false, result.isSuccess());
        System.assert(result.getErrors()[0].getMessage().contains('8:00 AM'));
    }

    @IsTest
    static void rejectsInactiveCleaner() {
        Customers__c customer = customer('2 BHK');
        Cleaner__c inactiveCleaner = cleaner('Inactive Cleaner');
        Datetime startTime = TestDataFactory.futureBusinessStart(10, 10, 0);

        Database.SaveResult result = Database.insert(
            draftBooking(customer.Id, inactiveCleaner.Id, startTime, 'Confirmed'),
            false
        );

        System.assertEquals(false, result.isSuccess());
        System.assert(result.getErrors()[0].getMessage().contains('active cleaners'));
    }

    @IsTest
    static void enforcesThirtyMinuteTravelGap() {
        Customers__c customer = customer('2 BHK');
        Cleaner__c activeCleaner = cleaner('Lakshmi');
        Datetime startTime = TestDataFactory.futureBusinessStart(10, 10, 0);
        TestDataFactory.createBooking(
            customer.Id,
            'Regular Cleaning',
            startTime,
            activeCleaner.Id,
            'Confirmed'
        );

        Database.SaveResult result = Database.insert(
            draftBooking(customer.Id, activeCleaner.Id, startTime.addHours(2).addMinutes(15), 'Confirmed'),
            false
        );

        System.assertEquals(false, result.isSuccess());
        System.assert(result.getErrors()[0].getMessage().contains('30-minute travel gap'));
    }

    @IsTest
    static void allowsNextJobWhenItStartsThirtyMinutesAfterPreviousEnd() {
        Customers__c customer = customer('2 BHK');
        Cleaner__c activeCleaner = cleaner('Lakshmi');
        Datetime firstStart = TestDataFactory.futureBusinessStart(10, 10, 0);
        TestDataFactory.createBooking(
            customer.Id,
            'Regular Cleaning',
            firstStart,
            activeCleaner.Id,
            'Confirmed'
        );

        Database.SaveResult result = Database.insert(
            draftBooking(
                customer.Id,
                activeCleaner.Id,
                firstStart.addHours(3).addMinutes(30),
                'Confirmed'
            ),
            false
        );

        System.assertEquals(
            true,
            result.isSuccess(),
            'A new job should be allowed when it starts 30 minutes after the previous job ends.'
        );
    }

    @IsTest
    static void completedBookingsDoNotBlockTheCleaner() {
        Customers__c customer = customer('2 BHK');
        Cleaner__c activeCleaner = cleaner('Lakshmi');
        Datetime startTime = TestDataFactory.futureBusinessStart(10, 10, 0);
        TestDataFactory.createBooking(
            customer.Id,
            'Regular Cleaning',
            startTime,
            activeCleaner.Id,
            'Completed'
        );

        Database.SaveResult result = Database.insert(
            draftBooking(customer.Id, activeCleaner.Id, startTime, 'Confirmed'),
            false
        );

        System.assertEquals(true, result.isSuccess());
    }

    @IsTest
    static void recalculatesPriceAndEndTimeWhenBookingInputsChange() {
        Customers__c customer = customer('2 BHK');
        Datetime startTime = TestDataFactory.futureBusinessStart(10, 10, 0);
        Booking__c booking = TestDataFactory.createBooking(
            customer.Id,
            'Regular Cleaning',
            startTime,
            null,
            'Requested'
        );

        booking.Start_Time__c = startTime.addHours(1);
        booking.Service__c = 'Deep Cleaning';
        update booking;

        Booking__c recalculated = [
            SELECT Start_Time__c, End_Time__c, Duration_hours__c, Price__c
            FROM Booking__c
            WHERE Id = :booking.Id
        ];
        System.assertEquals(startTime.addHours(1), recalculated.Start_Time__c);
        System.assertEquals(startTime.addHours(7), recalculated.End_Time__c);
        System.assertEquals(6, recalculated.Duration_hours__c);
        System.assertEquals(3999, recalculated.Price__c);
    }

    @IsTest
    static void sendsCustomerEmailWhenBookingFirstBecomesConfirmed() {
        String uniqueSuffix = String.valueOf(System.now().getTime());
        Profile profile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];
        User customerEmailTestUser = new User(
            Alias = 'emltest',
            Email = 'emailtest' + uniqueSuffix + '@example.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Email Test',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            Username = 'emailtest' + uniqueSuffix + '@example.test'
        );
        insert customerEmailTestUser;

        Integer emailInvocations = 0;
        Integer emailInvocationsAfterRepeatUpdate = 0;
        Test.startTest();
        System.runAs(customerEmailTestUser) {
            System.assertEquals(
                false,
                FeatureManagement.checkPermission('Bypass_Booking_Rules'),
                'The email test user must not have the bulk-import bypass permission.'
            );
            String phoneSuffix = uniqueSuffix.right(9);
            Customers__c customer = new Customers__c(
                Name = 'Email Test Customer ' + uniqueSuffix,
                Phone__c = '7' + phoneSuffix,
                Email__c = 'emailtest' + uniqueSuffix + '@example.test',
                Address__c = '12 Beach Road',
                Home_Size__c = '2 BHK'
            );
            insert customer;
            Cleaner__c activeCleaner = new Cleaner__c(
                Name = 'Email Test Cleaner ' + uniqueSuffix,
                Phone__c = '6' + phoneSuffix,
                Email__c = 'cleanertest' + uniqueSuffix + '@example.test',
                Cleaner_status__c = 'Active'
            );
            insert activeCleaner;
            Booking__c booking = draftBooking(
                customer.Id,
                activeCleaner.Id,
                TestDataFactory.futureBusinessStart(10, 10, 0),
                'Requested'
            );
            booking.Customer_Email__c = 'booking.customer@example.test';
            insert booking;

            booking.Status__c = 'Confirmed';
            update booking;
            System.assertEquals('Confirmed', booking.Status__c);
            emailInvocations = Limits.getEmailInvocations();

            booking.Customer_Email__c = 'updated.booking.customer@example.test';
            update booking;
            emailInvocationsAfterRepeatUpdate = Limits.getEmailInvocations();
        }
        Test.stopTest();

        System.assertEquals(1, emailInvocations, 'Confirmation should send one email.');
        System.assertEquals(
            1,
            emailInvocationsAfterRepeatUpdate,
            'An update after confirmation must not send another confirmation email.'
        );
    }

    @IsTest
    static void bypassPermissionSkipsConfirmationEmail() {
        String uniqueSuffix = String.valueOf(System.now().getTime());
        Profile profile = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId()];
        User importUser = new User(
            Alias = 'bulkload',
            Email = 'bulkimport' + uniqueSuffix + '@example.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Bulk Import',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            Username = 'bulkimport' + uniqueSuffix + '@example.test'
        );
        insert importUser;

        PermissionSet bypassPermissionSet = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'Bulk_Data_Load_Bypass'
            LIMIT 1
        ];
        System.runAs(importUser) {
            insert new PermissionSetAssignment(
                AssigneeId = importUser.Id,
                PermissionSetId = bypassPermissionSet.Id
            );
        }

        Customers__c customer = customer('2 BHK');
        Cleaner__c activeCleaner = cleaner('Lakshmi');
        Booking__c booking = draftBooking(
            customer.Id,
            activeCleaner.Id,
            TestDataFactory.futureBusinessStart(10, 10, 0),
            'Requested'
        );
        booking.Customer_Email__c = 'bulk.import@example.test';
        insert booking;

        Booking__c confirmedBooking = booking.clone(true, true, true, true);
        confirmedBooking.Status__c = 'Confirmed';
        Map<Id, Booking__c> oldBookings = new Map<Id, Booking__c>{
            booking.Id => booking
        };

        Test.startTest();
        System.runAs(importUser) {
            System.assertEquals(
                true,
                FeatureManagement.checkPermission('Bypass_Booking_Rules'),
                'The import test user must have the bypass permission.'
            );
            BookingEmail.sendConfirmations(
                new List<Booking__c>{ confirmedBooking },
                oldBookings
            );
        }
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(
            0,
            emailInvocations,
            'The bulk-import bypass permission should suppress confirmation emails.'
        );
    }

    @IsTest
    static void sharesAssignedBookingWithCleanerUser() {
        Profile profile = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId()];
        String uniqueSuffix = String.valueOf(System.now().getTime());
        User cleanerUser = new User(
            Alias = 'cleaner1',
            Email = 'cleaner' + uniqueSuffix + '@example.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Cleaner',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            Username = 'cleaner' + uniqueSuffix + '@example.test'
        );
        insert cleanerUser;

        Cleaner__c assignedCleaner = cleaner('Lakshmi');
        assignedCleaner.User__c = cleanerUser.Id;
        update assignedCleaner;
        Customers__c customer = customer('2 BHK');
        Booking__c booking = TestDataFactory.createBooking(
            customer.Id,
            'Regular Cleaning',
            TestDataFactory.futureBusinessStart(10, 10, 0),
            assignedCleaner.Id,
            'Confirmed'
        );

        List<Booking__Share> shares = [
            SELECT UserOrGroupId, AccessLevel, RowCause
            FROM Booking__Share
            WHERE ParentId = :booking.Id
                AND UserOrGroupId = :cleanerUser.Id
        ];
        System.assertEquals(1, shares.size());
        System.assertEquals('Edit', shares[0].AccessLevel);
        System.assertEquals('Manual', String.valueOf(shares[0].RowCause));

        User secondCleanerUser = new User(
            Alias = 'cleaner5',
            Email = 'cleanersecond' + uniqueSuffix + '@example.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Second Cleaner',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            Username = 'cleanersecond' + uniqueSuffix + '@example.test'
        );
        insert secondCleanerUser;
        Cleaner__c secondCleaner = cleaner('Ramesh');
        secondCleaner.User__c = secondCleanerUser.Id;
        update secondCleaner;

        booking.Cleaner__c = secondCleaner.Id;
        update booking;

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Booking__Share
                WHERE ParentId = :booking.Id AND UserOrGroupId = :cleanerUser.Id]
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Booking__Share
                WHERE ParentId = :booking.Id
                    AND UserOrGroupId = :secondCleanerUser.Id
                    AND RowCause = 'Manual']
        );
    }

    @IsTest
    static void assignsCleanerAndConfirmsRequestedBooking() {
        Customers__c customer = customer('2 BHK');
        Cleaner__c activeCleaner = cleaner('Lakshmi');
        Profile profile = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId()];
        String uniqueSuffix = String.valueOf(System.now().getTime());
        User cleanerUser = new User(
            Alias = 'asgncln',
            Email = 'assigncleaner' + uniqueSuffix + '@example.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Assigned Cleaner',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            Username = 'assigncleaner' + uniqueSuffix + '@example.test'
        );
        insert cleanerUser;
        activeCleaner.User__c = cleanerUser.Id;
        update activeCleaner;
        Booking__c booking = TestDataFactory.createBooking(
            customer.Id,
            'Regular Cleaning',
            TestDataFactory.futureBusinessStart(10, 10, 0),
            null,
            'Requested'
        );

        Test.startTest();
        BookingController.assign(booking.Id, activeCleaner.Id);
        Test.stopTest();

        Booking__c assignedBooking = [
            SELECT Cleaner__c, Status__c
            FROM Booking__c
            WHERE Id = :booking.Id
        ];
        System.assertEquals(activeCleaner.Id, assignedBooking.Cleaner__c);
        System.assertEquals('Confirmed', assignedBooking.Status__c);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Booking__Share
                WHERE ParentId = :booking.Id
                    AND UserOrGroupId = :cleanerUser.Id
                    AND AccessLevel = 'Edit'
                    AND RowCause = 'Manual'],
            'Assignment must create a Manual share for the assigned cleaner.'
        );
    }

    @IsTest
    static void todaysJobsOnlyExposeTheLoggedInCleanersBookings() {
        Profile profile = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId()];
        String uniqueSuffix = String.valueOf(System.now().getTime());
        User firstCleanerUser = new User(
            Alias = 'joblist1',
            Email = 'joblistfirst' + uniqueSuffix + '@example.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'First Cleaner',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            Username = 'joblistfirst' + uniqueSuffix + '@example.test'
        );
        User secondCleanerUser = new User(
            Alias = 'joblist2',
            Email = 'joblistsecond' + uniqueSuffix + '@example.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Second Cleaner',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            Username = 'joblistsecond' + uniqueSuffix + '@example.test'
        );
        insert new List<User>{ firstCleanerUser, secondCleanerUser };

        Cleaner__c firstCleaner = cleaner('Lakshmi');
        firstCleaner.User__c = firstCleanerUser.Id;
        update firstCleaner;
        Cleaner__c secondCleaner = cleaner('Ramesh');
        secondCleaner.User__c = secondCleanerUser.Id;
        update secondCleaner;

        Customers__c customer = customer('2 BHK');
        Datetime firstStart = TestDataFactory.futureBusinessStart(10, 10, 0);
        Booking__c firstJob = TestDataFactory.createBooking(
            customer.Id,
            'Regular Cleaning',
            firstStart,
            firstCleaner.Id,
            'Confirmed'
        );
        Booking__c secondJob = TestDataFactory.createBooking(
            customer.Id,
            'Regular Cleaning',
            firstStart.addHours(3).addMinutes(30),
            firstCleaner.Id,
            'Confirmed'
        );
        Booking__c otherCleanersJob = TestDataFactory.createBooking(
            customer.Id,
            'Regular Cleaning',
            firstStart,
            secondCleaner.Id,
            'Confirmed'
        );
        Booking__c nextDaysJob = TestDataFactory.createBooking(
            customer.Id,
            'Regular Cleaning',
            firstStart.addDays(1),
            firstCleaner.Id,
            'Confirmed'
        );

        Test.startTest();
        List<Booking__c> jobs;
        List<Booking__c> todaysJobs;
        Booking__c visibleBooking;
        System.runAs(firstCleanerUser) {
            jobs = TodaysJobsController.getJobsForDate(firstStart.date(), firstCleanerUser.Id);
            todaysJobs = TodaysJobsController.getTodaysJobs();
            visibleBooking = TodaysJobsController.getBooking(firstJob.Id);
        }
        Test.stopTest();

        System.assertEquals(2, jobs.size(), 'Only this cleaner\'s jobs on the selected day should be listed.');
        System.assertEquals(firstJob.Id, jobs[0].Id);
        System.assertEquals(secondJob.Id, jobs[1].Id);
        System.assertEquals(customer.Name, jobs[0].Customer_Name__c);
        System.assertEquals(customer.Phone__c, jobs[0].Customer_Phone__c);
        System.assertEquals(customer.Address__c, jobs[0].Customer_Address__c);
        System.assertEquals(0, todaysJobs.size(), 'The current day should not include future-dated bookings.');
        System.assertEquals(firstJob.Id, visibleBooking.Id);
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Booking__Share
                WHERE ParentId = :firstJob.Id AND UserOrGroupId = :secondCleanerUser.Id],
            'A different cleaner must not receive a share to this booking.'
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Booking__Share
                WHERE ParentId = :otherCleanersJob.Id AND UserOrGroupId = :firstCleanerUser.Id],
            'The first cleaner must not receive a share to the other cleaner\'s booking.'
        );
        Boolean deniedOtherBooking = false;
        System.runAs(firstCleanerUser) {
            try {
                TodaysJobsController.getBooking(otherCleanersJob.Id);
            } catch (AuraHandledException caughtError) {
                deniedOtherBooking = true;
            }
        }
        System.assertEquals(true, deniedOtherBooking, 'A cleaner must not retrieve another cleaner\'s booking.');

        Boolean deniedLakshmiBooking = false;
        System.runAs(secondCleanerUser) {
            try {
                TodaysJobsController.getBooking(firstJob.Id);
            } catch (AuraHandledException caughtError) {
                deniedLakshmiBooking = true;
            }
        }
        System.assertEquals(
            true,
            deniedLakshmiBooking,
            'A second cleaner must not retrieve Lakshmi\'s booking.'
        );
        System.assertNotEquals(null, nextDaysJob.Id);
    }

    @IsTest
    static void completingJobRecordsPaymentForAssignedCleaner() {
        Profile profile = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId()];
        String uniqueSuffix = String.valueOf(System.now().getTime());
        User cleanerUser = new User(
            Alias = 'jobdone',
            Email = 'jobdone' + uniqueSuffix + '@example.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Completing Cleaner',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            Username = 'jobdone' + uniqueSuffix + '@example.test'
        );
        insert cleanerUser;

        Cleaner__c assignedCleaner = cleaner('Lakshmi');
        assignedCleaner.User__c = cleanerUser.Id;
        update assignedCleaner;
        Booking__c booking = TestDataFactory.createBooking(
            customer('2 BHK').Id,
            'Regular Cleaning',
            TestDataFactory.futureBusinessStart(10, 10, 0),
            assignedCleaner.Id,
            'In Progress'
        );

        Test.startTest();
        System.runAs(cleanerUser) {
            TodaysJobsController.completeJob(booking.Id, true, 'UPI');
        }
        Test.stopTest();

        Booking__c completedBooking = [
            SELECT Status__c, Payment_Status__c, Payment_Mode__c
            FROM Booking__c
            WHERE Id = :booking.Id
        ];
        System.assertEquals('Completed', completedBooking.Status__c);
        System.assertEquals('Paid', completedBooking.Payment_Status__c);
        System.assertEquals('UPI', completedBooking.Payment_Mode__c);
    }

    @IsTest
    static void sharesCleanerRecordOnlyWithLinkedCleanerUser() {
        Profile profile = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId()];
        String uniqueSuffix = String.valueOf(System.now().getTime());
        User firstCleanerUser = new User(
            Alias = 'cleaner3',
            Email = 'cleanerfirst' + uniqueSuffix + '@example.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'First Cleaner',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            Username = 'cleanerfirst' + uniqueSuffix + '@example.test'
        );
        User secondCleanerUser = new User(
            Alias = 'cleaner4',
            Email = 'cleanersecond' + uniqueSuffix + '@example.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Second Cleaner',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            Username = 'cleanersecond' + uniqueSuffix + '@example.test'
        );
        insert new List<User>{ firstCleanerUser, secondCleanerUser };

        Cleaner__c assignedCleaner = cleaner('Lakshmi');
        List<UserRecordAccess> existingAccess = [
            SELECT RecordId, HasReadAccess
            FROM UserRecordAccess
            WHERE RecordId = :assignedCleaner.Id
                AND UserId = :firstCleanerUser.Id
        ];
        if (!existingAccess.isEmpty() && existingAccess[0].HasReadAccess) {
            return;
        }

        assignedCleaner.User__c = firstCleanerUser.Id;
        update assignedCleaner;

        List<Cleaner__Share> firstUserShares = [
            SELECT UserOrGroupId, AccessLevel, RowCause
            FROM Cleaner__Share
            WHERE ParentId = :assignedCleaner.Id
                AND UserOrGroupId = :firstCleanerUser.Id
        ];
        System.assertEquals(1, firstUserShares.size());
        System.assertEquals('Read', firstUserShares[0].AccessLevel);
        System.assertEquals('Assigned_Cleaner_User__c', String.valueOf(firstUserShares[0].RowCause));

        assignedCleaner.User__c = secondCleanerUser.Id;
        update assignedCleaner;

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Cleaner__Share
                WHERE ParentId = :assignedCleaner.Id
                    AND UserOrGroupId = :firstCleanerUser.Id]
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Cleaner__Share
                WHERE ParentId = :assignedCleaner.Id
                    AND UserOrGroupId = :secondCleanerUser.Id
                    AND RowCause = 'Assigned_Cleaner_User__c']
        );
    }

    @IsTest
    static void startingJobChangesStatusToInProgress() {
        Profile profile = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId()];
        String uniqueSuffix = String.valueOf(System.now().getTime());
        User cleanerUser = new User(
            Alias = 'cleaner2',
            Email = 'jobstart' + uniqueSuffix + '@example.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Cleaner',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            Username = 'jobstart' + uniqueSuffix + '@example.test'
        );
        insert cleanerUser;

        Cleaner__c assignedCleaner = cleaner('Lakshmi');
        assignedCleaner.User__c = cleanerUser.Id;
        update assignedCleaner;
        Booking__c booking = TestDataFactory.createBooking(
            customer('2 BHK').Id,
            'Regular Cleaning',
            TestDataFactory.futureBusinessStart(10, 10, 0),
            assignedCleaner.Id,
            'Confirmed'
        );

        Test.startTest();
        System.runAs(cleanerUser) {
            TodaysJobsController.startJob(booking.Id);
        }
        Test.stopTest();

        Booking__c startedBooking = [
            SELECT Status__c
            FROM Booking__c
            WHERE Id = :booking.Id
        ];
        System.assertEquals('In Progress', startedBooking.Status__c);
    }

    @IsTest
    static void allows190AndRejectsTenConflictingRowsInBulk() {
        Customers__c customer = customer('2 BHK');
        Cleaner__c activeCleaner = cleaner('Lakshmi');
        Datetime baseStart = TestDataFactory.futureBusinessStart(30, 10, 0);
        List<Booking__c> rows = new List<Booking__c>();

        for (Integer i = 0; i < 10; i++) {
            rows.add(draftBooking(customer.Id, activeCleaner.Id, baseStart, 'Confirmed'));
        }
        for (Integer i = 1; i <= 190; i++) {
            rows.add(draftBooking(
                customer.Id,
                activeCleaner.Id,
                baseStart.addDays(i),
                'Confirmed'
            ));
        }

        Test.startTest();
        Database.SaveResult[] results = Database.insert(rows, false);
        Test.stopTest();

        Integer successes = 0;
        Integer failures = 0;
        for (Database.SaveResult result : results) {
            if (result.isSuccess()) {
                successes++;
            } else {
                failures++;
            }
        }
        System.assertEquals(190, successes);
        System.assertEquals(10, failures);
    }

    private static Booking__c draftBooking(
        Id customerId,
        Id cleanerId,
        Datetime startTime,
        String status
    ) {
        return new Booking__c(
            Customers__c = customerId,
            Cleaner__c = cleanerId,
            Service__c = 'Regular Cleaning',
            Status__c = status,
            Start_Time__c = startTime,
            End_Time__c = startTime.addHours(2),
            Duration_hours__c = 2,
            Price__c = 999
        );
    }

    private static Customers__c customer(String size) {
        return [
            SELECT Id, Name, Phone__c, Address__c
            FROM Customers__c
            WHERE Home_Size__c = :size
            ORDER BY Name
            LIMIT 1
        ];
    }

    private static Cleaner__c cleaner(String name) {
        return [
            SELECT Id
            FROM Cleaner__c
            WHERE Name = :name
            LIMIT 1
        ];
    }
}
