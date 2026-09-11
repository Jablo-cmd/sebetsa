import { z } from 'zod';

const timePattern = /^([01]\d|2[0-3]):[0-5]\d$/;

export const availabilityWindowSchema = z
  .object({
    dayOfWeek: z.coerce.number().int().min(0).max(6),
    startTime: z.string().trim().regex(timePattern, 'Enter a valid time'),
    endTime: z.string().trim().regex(timePattern, 'Enter a valid time'),
  })
  .refine((values) => values.endTime > values.startTime, {
    message: 'End time must be after start time',
    path: ['endTime'],
  });

export type AvailabilityWindowFormValues = z.infer<typeof availabilityWindowSchema>;

export const availabilityWindowDefaultValues: AvailabilityWindowFormValues = {
  dayOfWeek: 1,
  startTime: '08:00',
  endTime: '17:00',
};

export const availabilityExceptionSchema = z
  .object({
    exceptionDate: z.string().trim().min(1, 'Date is required'),
    isAvailable: z.boolean(),
    startTime: z.string().trim().optional(),
    endTime: z.string().trim().optional(),
    reason: z.string().trim().optional(),
  })
  .refine((values) => !values.startTime || timePattern.test(values.startTime), {
    message: 'Enter a valid time',
    path: ['startTime'],
  })
  .refine((values) => !values.endTime || timePattern.test(values.endTime), {
    message: 'Enter a valid time',
    path: ['endTime'],
  })
  .refine((values) => !values.startTime || !values.endTime || values.endTime > values.startTime, {
    message: 'End time must be after start time',
    path: ['endTime'],
  });

export type AvailabilityExceptionFormValues = z.infer<typeof availabilityExceptionSchema>;

export const availabilityExceptionDefaultValues: AvailabilityExceptionFormValues = {
  exceptionDate: '',
  isAvailable: false,
  startTime: '',
  endTime: '',
  reason: '',
};
