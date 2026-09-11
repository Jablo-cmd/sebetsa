import { z } from 'zod';

const EMAIL_PATTERN = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

export const employeeSchema = z.object({
  employeeNumber: z.string().trim().min(1, 'Employee number is required'),
  firstName: z.string().trim().min(1, 'First name is required'),
  lastName: z.string().trim().min(1, 'Last name is required'),
  email: z
    .string()
    .trim()
    .optional()
    .refine((value) => !value || EMAIL_PATTERN.test(value), 'Enter a valid email address'),
  phone: z.string().trim().optional(),
  departmentId: z.string().trim().optional(),
  positionId: z.string().trim().optional(),
  employmentType: z
    .union([z.literal('full_time'), z.literal('part_time'), z.literal('contract'), z.literal('temporary'), z.literal('')])
    .optional(),
  employmentStartDate: z.string().trim().min(1, 'Start date is required'),
  supervisorId: z.string().trim().optional(),
});

export type EmployeeFormValues = z.infer<typeof employeeSchema>;

export const employeeDefaultValues: EmployeeFormValues = {
  employeeNumber: '',
  firstName: '',
  lastName: '',
  email: '',
  phone: '',
  departmentId: '',
  positionId: '',
  employmentType: '',
  employmentStartDate: '',
  supervisorId: '',
};
