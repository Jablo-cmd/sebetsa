import { z } from 'zod';

const timePattern = /^([01]\d|2[0-3]):[0-5]\d$/;

export const shiftSchema = z
  .object({
    siteId: z.string().trim().min(1, 'Site is required'),
    employeeId: z.string().trim().min(1, 'Employee is required'),
    supervisorId: z.string().trim().optional(),
    shiftDefinitionId: z.string().trim().optional(),
    date: z.string().trim().min(1, 'Date is required'),
    startTime: z.string().trim().regex(timePattern, 'Enter a valid time'),
    endTime: z.string().trim().regex(timePattern, 'Enter a valid time'),
    /** Only meaningful when endTime <= startTime: whether that means "ends the next day" (checked) rather than an invalid zero-length entry. */
    endsNextDay: z.boolean(),
    notes: z.string().trim().optional(),
  })
  .refine((values) => values.endTime !== values.startTime, {
    message: 'End time must differ from start time',
    path: ['endTime'],
  })
  .refine((values) => values.endTime > values.startTime || values.endsNextDay, {
    message: 'Check "Ends next day" for an overnight shift',
    path: ['endsNextDay'],
  });

export type ShiftFormValues = z.infer<typeof shiftSchema>;

export const shiftDefaultValues: ShiftFormValues = {
  siteId: '',
  employeeId: '',
  supervisorId: '',
  shiftDefinitionId: '',
  date: '',
  startTime: '08:00',
  endTime: '17:00',
  endsNextDay: false,
  notes: '',
};
