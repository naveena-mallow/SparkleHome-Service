import { LightningElement, api } from 'lwc';
import getCleanerTimeline from '@salesforce/apex/BookingController.getCleanerTimeline';
import assign from '@salesforce/apex/BookingController.assign';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class AssignCleaner extends LightningElement {
    cleaners = [];
    isLoading = true;
    isAssigning = false;
    errorMessage;
    _recordId;

    @api
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.load();
        }
    }

    get recordId() {
        return this._recordId;
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    get hasCleaners() {
        return this.cleaners.length > 0;
    }

    get timeLabels() {
        return Array.from({ length: 7 }, (_, index) => {
            const hour = 8 + (index * 2);
            return {
                key: hour,
                label: hour < 12 ? `${hour} AM` : `${hour === 12 ? 12 : hour - 12} PM`,
                style: `left: ${(index / 6) * 100}%`,
                className: index === 6 ? 'time-label time-label_end' : 'time-label'
            };
        });
    }

    async load() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const results = await getCleanerTimeline({ bookingId: this.recordId });
            this.cleaners = results.map((cleaner) => {
                const blocks = cleaner.jobs
                    .map((job) => {
                        const start = Math.max(0, job.startOffsetMinutes);
                        const end = Math.min(720, job.endOffsetMinutes);
                        if (end <= start) {
                            return null;
                        }

                        const left = (start / 720) * 100;
                        const width = ((end - start) / 720) * 100;
                        const gapEnd = Math.min(720, end + 30);
                        return {
                            ...job,
                            style: `left: ${left}%; width: ${width}%;`,
                            title: `${job.bookingName} · ${job.status}`,
                            className: `job-block job-block_${job.status.toLowerCase().replaceAll(' ', '-')}`,
                            travelStyle: `left: ${(end / 720) * 100}%; width: ${((gapEnd - end) / 720) * 100}%;`
                        };
                    })
                    .filter(Boolean);

                return {
                    ...cleaner,
                    timelineJobs: blocks,
                    travelBlocks: blocks.map((job) => ({
                        key: `${job.bookingId}-travel`,
                        style: job.travelStyle
                    }))
                };
            });
        } catch (error) {
            this.cleaners = [];
            this.errorMessage = this.reduceError(error);
            this.showToast('Unable to load cleaners', this.errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleAssign(event) {
        this.isAssigning = true;
        try {
            await assign({
                bookingId: this.recordId,
                cleanerId: event.currentTarget.dataset.id
            });
            this.showToast('Success', 'Cleaner assigned and booking confirmed.', 'success');
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            this.showToast('Unable to assign cleaner', this.reduceError(error), 'error');
        } finally {
            this.isAssigning = false;
        }
    }

    reduceError(error) {
        const body = error?.body;
        if (typeof body === 'string') {
            return body;
        }

        const messages = [];
        if (Array.isArray(body)) {
            messages.push(...body.map((item) => item?.message));
        } else if (body && typeof body === 'object') {
            messages.push(body.message);
            messages.push(...(body.pageErrors || []).map((item) => item?.message));
            messages.push(
                ...Object.values(body.fieldErrors || {})
                    .flat()
                    .map((item) => item?.message)
            );
            messages.push(...(body.output?.errors || []).map((item) => item?.message));
            messages.push(
                ...Object.values(body.output?.fieldErrors || {})
                    .flat()
                    .map((item) => item?.message)
            );
        }
        messages.push(error?.message);

        const uniqueMessages = [...new Set(messages.filter(Boolean))];
        return uniqueMessages.length
            ? uniqueMessages.join(' ')
            : 'An unexpected error occurred.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
