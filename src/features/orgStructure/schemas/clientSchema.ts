import { z } from 'zod';

const EMAIL_PATTERN = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

export const clientSchema = z.object({
  name: z.string().trim().min(1, 'Name is required'),
  regionId: z.string().trim().optional(),
  industry: z.string().trim().optional(),
  primaryContactName: z.string().trim().optional(),
  primaryContactEmail: z
    .string()
    .trim()
    .optional()
    .refine((value) => !value || EMAIL_PATTERN.test(value), 'Enter a valid email address'),
  primaryContactPhone: z.string().trim().optional(),
});

export type ClientFormValues = z.infer<typeof clientSchema>;

export const clientDefaultValues: ClientFormValues = {
  name: '',
  regionId: '',
  industry: '',
  primaryContactName: '',
  primaryContactEmail: '',
  primaryContactPhone: '',
};
