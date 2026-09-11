import { z } from 'zod';

export const siteAssignmentSchema = z
  .object({
    siteId: z.string().trim().min(1, 'Site is required'),
    employeeId: z.string().trim().min(1, 'Employee is required'),
    roleOnSite: z.string().trim().optional(),
    startDate: z.string().trim().min(1, 'Start date is required'),
    endDate: z.string().trim().optional(),
  })
  .refine((values) => !values.endDate || values.endDate >= values.startDate, {
    message: 'End date must be on or after the start date',
    path: ['endDate'],
  });

export type SiteAssignmentFormValues = z.infer<typeof siteAssignmentSchema>;

export const siteAssignmentDefaultValues: SiteAssignmentFormValues = {
  siteId: '',
  employeeId: '',
  roleOnSite: '',
  startDate: '',
  endDate: '',
};
