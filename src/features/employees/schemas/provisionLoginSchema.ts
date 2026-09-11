import { z } from 'zod';
import { PROVISIONABLE_ROLES } from '@/features/employees/types/employee.types';

export const provisionLoginSchema = z.object({
  role: z.enum(PROVISIONABLE_ROLES, { errorMap: () => ({ message: 'Select a role' }) }),
  phone: z.string().trim().optional(),
});

export type ProvisionLoginFormValues = z.infer<typeof provisionLoginSchema>;

export const provisionLoginDefaultValues: ProvisionLoginFormValues = {
  role: 'employee',
  phone: '',
};
