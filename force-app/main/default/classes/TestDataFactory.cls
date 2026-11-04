@IsTest
public class TestDataFactory {
    private static Integer customerSequence = 0;
    private static Integer cleanerSequence = 0;

    public static void createRateCards() {
        insert new List<Rate_Card__c>{
            rateCard('Regular Cleaning', '1 BHK', 999, 2),
            rateCard('Regular Cleaning', '2 BHK', 1499, 3),
            rateCard('Regular Cleaning', '3 BHK', 1999, 4),
            rateCard('Deep Cleaning', '1 BHK', 2999, 4),
            rateCard('Deep Cleaning', '2 BHK', 3999, 6),
            rateCard('Deep Cleaning', '3 BHK', 4999, 8),
            rateCard('Kitchen Cleaning', '1 BHK', 1199, 2),
            rateCard('Kitchen Cleaning', '2 BHK', 1199, 2),
            rateCard('Kitchen Cleaning', '3 BHK', 1499, 2.5)
        };
    }

    public static Customers__c createCustomer(String size) {
        customerSequence++;
        Customers__c customer = new Customers__c(
            Name = 'Test Customer ' + customerSequence,
            Phone__c = '8' + String.valueOf(100000000 + customerSequence).right(9),
            Email__c = 'customer' + customerSequence + '@example.test',
            Address__c = '12 Beach Road',
            Home_Size__c = size
        );
        insert customer;
        return customer;
    }

    public static Cleaner__c createCleaner(String name, Boolean active) {
        cleanerSequence++;
        Cleaner__c cleaner = new Cleaner__c(
            Name = name,
            Phone__c = '9' + String.valueOf(100000000 + cleanerSequence).right(9),
            Email__c = 'cleaner' + cleanerSequence + '@example.test',
            Cleaner_status__c = active ? 'Active' : 'Inactive'
        );
        insert cleaner;
        return cleaner;
    }

    public static Booking__c createBooking(
        Id customerId,
        String service,
        Datetime startTime,
        Id cleanerId,
        String status
    ) {
        Booking__c booking = new Booking__c(
            Customers__c = customerId,
            Cleaner__c = cleanerId,
            Service__c = service,
            Status__c = status,
            Start_Time__c = startTime,
            End_Time__c = startTime.addHours(2),
            Duration_hours__c = 2,
            Price__c = 999
        );
        insert booking;
        return booking;
    }

    public static Datetime futureBusinessStart(Integer daysAhead, Integer hour, Integer minute) {
        Date indiaDate = Date.valueOf(System.now().format('yyyy-MM-dd', 'Asia/Kolkata'))
            .addDays(daysAhead);
        return Datetime.newInstanceGmt(
            indiaDate,
            Time.newInstance(hour, minute, 0, 0)
        ).addMinutes(-330);
    }

    private static Rate_Card__c rateCard(
        String service,
        String size,
        Decimal price,
        Decimal duration
    ) {
        return new Rate_Card__c(
            Service__c = service,
            Home_Size__c = size,
            Price__c = price,
            Duration_hours__c = duration
        );
    }
}
