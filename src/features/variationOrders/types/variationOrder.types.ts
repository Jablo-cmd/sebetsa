import type { Database } from '@/lib/database.types';

export type ServiceRequestType = Database['public']['Enums']['service_request_type'];
export type ServiceRequestStatus = Database['public']['Enums']['service_request_status'];
export type ServiceRequestOrigin = Database['public']['Enums']['service_request_origin'];
export type VariationOrderStatus = Database['public']['Enums']['variation_order_status'];
export type TaskPriority = Database['public']['Enums']['task_priority'];

export interface ServiceRequest {
  id: string;
  tenantId: string;
  clientId: string;
  siteId: string | null;
  contractId: string | null;
  requestedBy: string | null;
  requestType: ServiceRequestType;
  description: string;
  requestedDate: string | null;
  priority: TaskPriority;
  status: ServiceRequestStatus;
  origin: ServiceRequestOrigin;
  resolvedAt: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface CreateServiceRequestInput {
  clientId: string;
  siteId?: string | null;
  contractId?: string | null;
  requestType?: ServiceRequestType;
  description: string;
  requestedDate?: string | null;
  priority?: TaskPriority;
}

export interface VariationOrder {
  id: string;
  tenantId: string;
  serviceRequestId: string | null;
  clientId: string;
  contractId: string;
  siteId: string;
  title: string;
  description: string | null;
  reason: string | null;
  status: VariationOrderStatus;
  quoteId: string | null;
  approvedBy: string | null;
  approvedAt: string | null;
  taskId: string | null;
  createdBy: string | null;
  createdAt: string;
  updatedAt: string;
  completedAt: string | null;
}
