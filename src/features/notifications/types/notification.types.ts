export interface Notification {
  id: string;
  tenantId: string | null;
  recipientProfileId: string;
  type: string;
  title: string;
  body: string;
  relatedEntityTable: string | null;
  relatedEntityId: string | null;
  linkPath: string | null;
  isRead: boolean;
  createdAt: string;
}
