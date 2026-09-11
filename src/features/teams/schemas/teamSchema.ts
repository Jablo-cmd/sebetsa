import { z } from 'zod';

export const teamSchema = z.object({
  name: z.string().trim().min(1, 'Name is required'),
  siteId: z.string().trim().optional(),
  leadEmployeeId: z.string().trim().optional(),
});

export type TeamFormValues = z.infer<typeof teamSchema>;

export const teamDefaultValues: TeamFormValues = {
  name: '',
  siteId: '',
  leadEmployeeId: '',
};
