import { z } from 'zod';

export const organizationCreateSchema = z.object({
  name: z.string().trim().min(2, 'Organization name must be at least 2 characters'),
  industry: z.string().trim().optional(),
  status: z.enum(['pending', 'active', 'inactive', 'suspended']),
});

export type OrganizationCreateFormValues = z.infer<typeof organizationCreateSchema>;

export const organizationCreateDefaultValues: OrganizationCreateFormValues = {
  name: '',
  industry: '',
  status: 'active',
};
