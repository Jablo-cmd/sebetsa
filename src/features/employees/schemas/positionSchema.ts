import { z } from 'zod';

export const positionSchema = z.object({
  title: z.string().trim().min(1, 'Title is required'),
  departmentId: z.string().trim().optional(),
});

export type PositionFormValues = z.infer<typeof positionSchema>;

export const positionDefaultValues: PositionFormValues = {
  title: '',
  departmentId: '',
};
