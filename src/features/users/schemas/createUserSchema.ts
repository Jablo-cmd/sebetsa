import { z } from 'zod';
import { ASSIGNABLE_ROLES } from '@/features/users/types/user.types';

export const createUserSchema = z.object({
  firstName: z.string().trim().min(1, 'First name is required'),
  lastName: z.string().trim().min(1, 'Last name is required'),
  email: z.string().trim().min(1, 'Email is required').email('Enter a valid email address'),
  phone: z.string().trim().optional(),
  role: z.enum(ASSIGNABLE_ROLES, { errorMap: () => ({ message: 'Select a role' }) }),
});

export type CreateUserFormValues = z.infer<typeof createUserSchema>;

export const createUserDefaultValues: CreateUserFormValues = {
  firstName: '',
  lastName: '',
  email: '',
  phone: '',
  role: 'employee',
};