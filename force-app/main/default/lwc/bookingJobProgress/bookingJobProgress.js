import { api, LightningElement, wire } from 'lwc';
import getBooking from '@salesforce/apex/TodaysJobsController.getBooking';
import startJob from '@salesforce/apex/TodaysJobsController.startJob';
import completeJob from '@salesforce/apex/TodaysJobsController.completeJob';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const PAYMENT_MODES = [
    { label: 'Cash', value: 'Cash', detail: 'Customer paid in cash' },
    { label: 'UPI', value: 'UPI', detail: 'Customer paid digitally' },
    { label: 'Not Paid', value: 'UNPAID', detail: 'Payment is still due' }
];

export default class BookingJobProgress extends LightningElement {
    @api recordId;

    booking;
    bookingWireResult;
    showPaymentModal = false;
    paymentMode = 'UPI';
    isLoading = true;
    isUpdating = false;
    errorMessage;

    @wire(getBooking, { bookingId: '$recordId' })
    wiredBooking(result) {
        this.bookingWireResult = result;
        const { data, error } = result;
        if (data) {
            this.booking = this.prepareBooking(data);
            this.errorMessage = undefined;
            this.isLoading = false;
        } else if (error) {
            this.booking = undefined;
            this.errorMessage = this.message(error);
            this.isLoading = false;
        }
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    get paymentOptions() {
        return PAYMENT_MODES.map((option) => ({
            ...option,
            className: this.paymentMode === option.value
                ? 'payment-option payment-option_selected'
                : 'payment-option',
            selected: this.paymentMode === option.value
        }));
    }

    prepareBooking(row) {
        const startTime = row.Start_Time__c ? new Date(row.Start_Time__c) : null;
        const endTime = row.End_Time__c ? new Date(row.End_Time__c) : null;
        const validStart = Number.isFinite(startTime?.getTime());
        const validEnd = Number.isFinite(endTime?.getTime());
        return {
            ...row,
            phoneLink: row.Customer_Phone__c ? `tel:${row.Customer_Phone__c}` : undefined,
            timeLabel: validStart
                ? `${this.formatTime(startTime)}${validEnd ? ` - ${this.formatTime(endTime)}` : ''}`
                : 'Schedule unavailable',
            canStart: row.Status__c === 'Confirmed',
            canComplete: row.Status__c === 'In Progress',
            isCompleted: row.Status__c === 'Completed',
            isCancelled: row.Status__c === 'Cancelled',
            hasCancellationReason: Boolean(row.Cancellation_Reason__c)
        };
    }

    async handleStart() {
        this.isUpdating = true;
        try {
            await startJob({ bookingId: this.recordId });
            this.toast('Success', 'Job started.', 'success');
            await this.refreshBooking();
        } catch (error) {
            this.toast('Unable to start job', this.message(error), 'error');
        } finally {
            this.isUpdating = false;
        }
    }

    openPayment() {
        this.paymentMode = 'UPI';
        this.showPaymentModal = true;
    }

    closePayment() {
        this.showPaymentModal = false;
    }

    handlePaymentMode(event) {
        this.paymentMode = event.currentTarget.dataset.mode;
    }

    async completeJob() {
        this.isUpdating = true;
        try {
            const paid = this.paymentMode !== 'UNPAID';
            await completeJob({
                bookingId: this.recordId,
                paid,
                paymentMode: paid ? this.paymentMode : null
            });
            this.toast('Success', 'Job completed.', 'success');
            this.closePayment();
            await this.refreshBooking();
        } catch (error) {
            this.toast('Unable to complete job', this.message(error), 'error');
        } finally {
            this.isUpdating = false;
        }
    }

    async refreshBooking() {
        try {
            await refreshApex(this.bookingWireResult);
        } catch (error) {
            this.toast(
                'Booking refresh warning',
                `The job was saved, but the booking could not be refreshed: ${this.message(error)}`,
                'warning'
            );
        }
    }

    formatTime(value) {
        return new Intl.DateTimeFormat('en-IN', {
            hour: 'numeric',
            minute: '2-digit',
            timeZone: 'Asia/Kolkata'
        }).format(value);
    }

    message(error) {
        return error?.body?.message || error?.message || 'An unexpected error occurred.';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
