import { z } from 'zod';

export const regionSchema = z.object({
  name: z.string().trim().min(1, 'Name is required'),
  code: z.string().trim().optional(),
});

export type RegionFormValues = z.infer<typeof regionSchema>;

export const regionDefaultValues: RegionFormValues = {
  name: '',
  code: '',
};
