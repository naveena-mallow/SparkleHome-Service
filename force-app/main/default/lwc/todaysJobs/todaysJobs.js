import { LightningElement, wire } from 'lwc';
import getTodaysJobs from '@salesforce/apex/TodaysJobsController.getTodaysJobs';
import startJob from '@salesforce/apex/TodaysJobsController.startJob';
import completeJob from '@salesforce/apex/TodaysJobsController.completeJob';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const PAYMENT_MODES = [
    { label: 'Cash', value: 'Cash', detail: 'Customer paid in cash' },
    { label: 'UPI', value: 'UPI', detail: 'Customer paid digitally' },
    { label: 'Not Paid', value: 'UNPAID', detail: 'Payment is still due' }
];

export default class TodaysJobs extends LightningElement {
    jobs = [];
    jobsWireResult;
    selectedBookingId;
    showPaymentModal = false;
    paymentMode = 'UPI';
    isLoading = true;
    isUpdating = false;
    errorMessage;

    get hasJobs() {
        return this.jobs.length > 0;
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    @wire(getTodaysJobs)
    wiredJobs(result) {
        this.jobsWireResult = result;
        const { data, error } = result;
        if (data) {
            this.jobs = data.map((row) => this.prepareJob(row));
            this.errorMessage = undefined;
            this.isLoading = false;
        } else if (error) {
            this.jobs = [];
            this.errorMessage = this.message(error);
            this.isLoading = false;
            this.toast('Unable to load today\'s jobs', this.errorMessage, 'error');
        }
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

    prepareJob(row) {
        const startTime = row.Start_Time__c ? new Date(row.Start_Time__c) : null;
        const endTime = row.End_Time__c ? new Date(row.End_Time__c) : null;
        const startMs = startTime?.getTime();
        const endMs = endTime?.getTime();
        const validStart = Number.isFinite(startMs);
        const validEnd = Number.isFinite(endMs);
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

    async handleStart(event) {
        this.isUpdating = true;
        try {
            await startJob({ bookingId: event.currentTarget.dataset.id });
            this.toast('Success', 'Job started.', 'success');
            await this.refreshJobs();
        } catch (error) {
            this.toast('Unable to start job', this.message(error), 'error');
        } finally {
            this.isUpdating = false;
        }
    }

    openPayment(event) {
        this.paymentMode = 'UPI';
        this.selectedBookingId = event.currentTarget.dataset.id;
        this.showPaymentModal = true;
    }

    closePayment() {
        this.showPaymentModal = false;
        this.selectedBookingId = undefined;
    }

    handlePaymentMode(event) {
        this.paymentMode = event.currentTarget.dataset.mode;
    }

    async completeJob() {
        this.isUpdating = true;
        try {
            const paid = this.paymentMode !== 'UNPAID';
            await completeJob({
                bookingId: this.selectedBookingId,
                paid,
                paymentMode: paid ? this.paymentMode : null
            });
            this.toast('Success', 'Job completed.', 'success');
            this.closePayment();
            await this.refreshJobs();
        } catch (error) {
            this.toast('Unable to complete job', this.message(error), 'error');
        } finally {
            this.isUpdating = false;
        }
    }

    async refreshJobs() {
        try {
            await refreshApex(this.jobsWireResult);
        } catch (error) {
            this.toast(
                'Jobs refresh warning',
                `The job was saved, but today\'s jobs could not be refreshed: ${this.message(error)}`,
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
