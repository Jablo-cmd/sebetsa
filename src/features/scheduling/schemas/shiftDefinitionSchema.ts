import { z } from 'zod';

const timePattern = /^([01]\d|2[0-3]):[0-5]\d$/;

export const shiftDefinitionSchema = z.object({
  name: z.string().trim().min(1, 'Name is required'),
  startTime: z.string().trim().regex(timePattern, 'Enter a valid time'),
  endTime: z.string().trim().regex(timePattern, 'Enter a valid time'),
  isOvernight: z.boolean(),
  breakMinutes: z.coerce.number().int('Whole minutes only').min(0, 'Cannot be negative'),
});

export type ShiftDefinitionFormValues = z.infer<typeof shiftDefinitionSchema>;

export const shiftDefinitionDefaultValues: ShiftDefinitionFormValues = {
  name: '',
  startTime: '08:00',
  endTime: '17:00',
  isOvernight: false,
  breakMinutes: 0,
};
