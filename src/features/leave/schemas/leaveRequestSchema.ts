import { z } from 'zod';

export const leaveRequestSchema = z
  .object({
    leaveTypeId: z.string().trim().min(1, 'Leave type is required'),
    startDate: z.string().trim().min(1, 'Start date is required'),
    endDate: z.string().trim().min(1, 'End date is required'),
    isHalfDay: z.boolean(),
    halfDayPeriod: z.union([z.literal('am'), z.literal('pm'), z.literal('')]),
    reason: z.string().trim().max(2000).optional(),
    supportingDocumentRef: z.string().trim().max(500).optional(),
  })
  .refine((values) => values.endDate >= values.startDate, {
    message: 'End date must not be before start date',
    path: ['endDate'],
  })
  .refine((values) => !values.isHalfDay || values.startDate === values.endDate, {
    message: 'A half-day request must have the same start and end date',
    path: ['endDate'],
  })
  .refine((values) => !values.isHalfDay || values.halfDayPeriod !== '', {
    message: 'Select morning or afternoon',
    path: ['halfDayPeriod'],
  });

export type LeaveRequestFormValues = z.infer<typeof leaveRequestSchema>;

export const leaveRequestDefaultValues: LeaveRequestFormValues = {
  leaveTypeId: '',
  startDate: '',
  endDate: '',
  isHalfDay: false,
  halfDayPeriod: '',
  reason: '',
  supportingDocumentRef: '',
};
