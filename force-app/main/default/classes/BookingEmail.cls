public without sharing class BookingEmail {
    public static void sendConfirmations(
        List<Booking__c> records,
        Map<Id, Booking__c> oldMap
    ) {
        if (FeatureManagement.checkPermission('Bypass_Booking_Rules')) {
            return;
        }

        Set<Id> bookingIds = new Set<Id>();
        for (Booking__c booking : records) {
            Booking__c oldBooking = oldMap == null ? null : oldMap.get(booking.Id);
            if (booking.Status__c == 'Confirmed'
                && (oldBooking == null || oldBooking.Status__c != 'Confirmed')) {
                bookingIds.add(booking.Id);
            }
        }

        if (bookingIds.isEmpty()) {
            return;
        }

        Tax_Config__mdt taxConfig = Tax_Config__mdt.getInstance('Default_GST');
        String gstLabel = 'GST';
        if (taxConfig != null && taxConfig.GST_Percentage__c != null) {
            Decimal gstPercentage = taxConfig.GST_Percentage__c;
            String percentageText = gstPercentage == gstPercentage.setScale(0)
                ? String.valueOf(gstPercentage.setScale(0))
                : String.valueOf(gstPercentage);
            gstLabel = 'GST (' + percentageText + '%)';
        }

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Booking__c booking : [
            SELECT Id, Name, Service__c, Start_Time__c, Duration_hours__c,
                Price__c, GST__c, Total__c, Customer_Name__c, Customer_Phone__c,
                Customer_Address__c, Customer_Email__c, Cleaner__r.Name
            FROM Booking__c
            WHERE Id IN :bookingIds
        ]) {
            if (String.isBlank(booking.Customer_Email__c)) {
                continue;
            }

            String html =
                '<div style="margin:0;padding:20px;background:#f4f5f7;font-family:Arial,sans-serif;">'
                + '<table width="100%" cellpadding="0" cellspacing="0"><tr><td align="center">'
                + '<table width="700" cellpadding="0" cellspacing="0" style="background:white;border-radius:12px;">'
                + '<tr><td style="padding:35px;">'
                + '<h2 style="color:#2e7d32;margin-bottom:10px;">Booking Confirmed</h2>'
                + '<p style="font-size:16px;color:#555;">Hello '
                + escapeHtml(booking.Customer_Name__c) + ',</p>'
                + '<p style="font-size:16px;color:#555;">Your SparkleHome cleaning booking has been confirmed.</p>'
                + '</td></tr><tr><td style="padding:0 35px 20px;">'
                + '<div style="background:#f5f7fb;padding:20px;border-radius:10px;">'
                + '<strong>Booking Number</strong><br>' + escapeHtml(booking.Name)
                + '<br><br><strong>Service</strong><br>' + escapeHtml(booking.Service__c)
                + '<br><br><strong>Cleaner</strong><br>'
                + escapeHtml(booking.Cleaner__r == null ? null : booking.Cleaner__r.Name)
                + '<br><br><strong>Date &amp; Time</strong><br>'
                + booking.Start_Time__c.format('dd MMM yyyy, hh:mm a', 'Asia/Kolkata') + ' IST'
                + '<br><br><strong>Duration</strong><br>'
                + String.valueOf(booking.Duration_hours__c) + ' Hours'
                + '</div></td></tr><tr><td style="padding:0 35px 20px;">'
                + '<div style="background:#fff8e6;padding:20px;border-radius:10px;">'
                + '<strong>Price</strong><br>₹ ' + formatAmount(booking.Price__c)
                + '<br><br><strong>' + gstLabel + '</strong><br>₹ ' + formatAmount(booking.GST__c)
                + '<br><br><strong>Total Amount</strong><br>'
                + '<span style="font-size:24px;font-weight:bold;color:#2e7d32;">₹ '
                + formatAmount(booking.Total__c) + '</span>'
                + '</div></td></tr><tr><td style="padding:0 35px 20px;">'
                + '<div style="background:#f5f7fb;padding:20px;border-radius:10px;">'
                + '<strong>Customer Name</strong><br>' + escapeHtml(booking.Customer_Name__c)
                + '<br><br><strong>Customer Phone</strong><br>' + escapeHtml(booking.Customer_Phone__c)
                + '<br><br><strong>Address</strong><br>' + escapeHtml(booking.Customer_Address__c)
                + '</div></td></tr><tr><td style="padding:25px 35px;color:#777;">'
                + 'Thank you for choosing <strong>SparkleHome Services</strong>.'
                + '<br><br>We look forward to serving you.'
                + '</td></tr></table></td></tr></table></div>';

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ booking.Customer_Email__c });
            email.setSubject('Booking Confirmed - ' + booking.Name);
            email.setHtmlBody(html);
            emails.add(email);
        }

        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails, false);
        }
    }

    private static String escapeHtml(String value) {
        String escaped = value == null ? '' : value;
        escaped = escaped.replace('&', '&amp;');
        escaped = escaped.replace('<', '&lt;');
        escaped = escaped.replace('>', '&gt;');
        escaped = escaped.replace('"', '&quot;');
        return escaped.replace('\'', '&#39;');
    }

    private static String formatAmount(Decimal value) {
        return value == null ? '0.00' : String.valueOf(value.setScale(2));
    }
}
