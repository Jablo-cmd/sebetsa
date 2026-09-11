import { z } from 'zod';

export const contractSchema = z
  .object({
    clientId: z.string().trim().min(1, 'Client is required'),
    contractNumber: z.string().trim().min(1, 'Contract number is required'),
    startDate: z.string().trim().min(1, 'Start date is required'),
    endDate: z.string().trim().optional(),
    responsibleManagerId: z.string().trim().optional(),
    slaNotes: z.string().trim().optional(),
    siteIds: z.array(z.string()).default([]),
  })
  .refine((values) => !values.endDate || values.endDate >= values.startDate, {
    message: 'End date must be on or after the start date',
    path: ['endDate'],
  });

export type ContractFormValues = z.infer<typeof contractSchema>;

export const contractDefaultValues: ContractFormValues = {
  clientId: '',
  contractNumber: '',
  startDate: '',
  endDate: '',
  responsibleManagerId: '',
  slaNotes: '',
  siteIds: [],
};
