
SparkleHome – Home Cleaning Services Management System

Project Overview

SparkleHome is a Salesforce-based application that simplifies home cleaning operations by managing customers, bookings, cleaners, pricing, scheduling, and payments in one place.

It replaces manual notebook and WhatsApp-based booking management with an automated system that reduces scheduling conflicts and improves operational efficiency.

Key Features

- Manage customers, cleaners, and bookings.
- Automatically calculate cleaning price, duration, GST, and total amount using rate cards.
- Prevent double-booking and enforce a 30-minute travel gap between jobs.
- Validate booking schedules based on IST business hours.
- Display available cleaners through the Assign Cleaner screen.
- Provide cleaners with a mobile-friendly Today's Jobs screen.
- Track payment status and payment methods (Cash/UPI).
- Send booking confirmation emails.
- Generate reports and dashboards for operations managers.
- Control record access using role-based permissions and Apex-managed sharing.

Key Design Decisions

1. Data Security: Private sharing ensures cleaners can access only their assigned bookings.
2. Conflict Prevention: Apex validations and record locking prevent scheduling conflicts.
3. Fixed Pricing: Booking prices and durations remain unchanged even if rate cards are updated.
4. IST Scheduling: All booking validations follow India Standard Time.
5. Payment Tracking: Supports Paid and Unpaid bookings with Cash and UPI payment methods.
6. Mobile Experience: Today's Jobs is designed for easy access by cleaners.


Setup

1. Create a Salesforce Developer Edition org.
2. Deploy project metadata.
3. Create and assign Booking Agent, Cleaner, and Operations Manager permission sets.
4. Create test users and link cleaner records to Salesforce users.
5. Enable email deliverability.
6. Load sample data and execute the seed script.
7. Verify Assign Cleaner, Today's Jobs, reports, and dashboard.
8. Run Apex tests and verify code coverage.

Testing

Apex test classes cover booking creation, pricing calculations, GST, cleaner availability, scheduling conflicts, sharing, and payment handling.


Testing coverage:
<img width="1466" height="483" alt="Screenshot 2026-11-04 at 10 39 30 PM" src="https://github.com/user-attachments/assets/d66e19b5-9ddb-4b87-ad4f-3101f16110b6" />
