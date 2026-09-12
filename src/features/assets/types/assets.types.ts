import type { AssetStatusEnum, InventoryMovementTypeEnum, ProcurementStatusEnum } from '@/lib/dbTypes';

export interface Asset {
  id: string;
  tenantId: string;
  assetNumber: string;
  name: string;
  category: string;
  serialNumber: string | null;
  siteId: string | null;
  custodianEmployeeId: string | null;
  status: AssetStatusEnum;
  condition: string | null;
  acquisitionDate: string | null;
  acquisitionCost: number | null;
  notes: string | null;
}

export interface InventoryItem {
  id: string;
  tenantId: string;
  sku: string;
  name: string;
  category: string;
  unit: string;
  reorderThreshold: number | null;
  isActive: boolean;
}

export interface InventoryMovement {
  id: string;
  tenantId: string;
  itemId: string;
  siteId: string;
  movementType: InventoryMovementTypeEnum;
  quantity: number;
  reference: string | null;
  createdAt: string;
}

export interface ProcurementRequest {
  id: string;
  tenantId: string;
  requestedBy: string | null;
  siteId: string | null;
  itemDescription: string;
  quantity: number;
  estimatedCost: number | null;
  status: ProcurementStatusEnum;
  approvedBy: string | null;
  approvedAt: string | null;
  rejectedReason: string | null;
  createdAt: string;
}

export const ASSET_STATUS_LABELS: Record<AssetStatusEnum, string> = {
  available: 'Available',
  assigned: 'Assigned',
  maintenance: 'Maintenance',
  lost: 'Lost',
  damaged: 'Damaged',
  retired: 'Retired',
  disposed: 'Disposed',
};

export const PROCUREMENT_STATUS_LABELS: Record<ProcurementStatusEnum, string> = {
  requested: 'Requested',
  submitted: 'Submitted',
  approved: 'Approved',
  rejected: 'Rejected',
  ordered: 'Ordered',
  received: 'Received',
  completed: 'Completed',
  cancelled: 'Cancelled',
};
