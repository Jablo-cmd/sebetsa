import { z } from 'zod';

export const siteSchema = z.object({
  name: z.string().trim().min(1, 'Name is required'),
  clientId: z.string().trim().min(1, 'Client is required'),
  regionId: z.string().trim().optional(),
  address: z.string().trim().optional(),
  siteType: z.string().trim().optional(),
});

export type SiteFormValues = z.infer<typeof siteSchema>;

export const siteDefaultValues: SiteFormValues = {
  name: '',
  clientId: '',
  regionId: '',
  address: '',
  siteType: '',
};
