/**
 * Domain types for panic/duress/emergency response
 * (supabase/migrations/20260921090300_emergency_response.sql). Treated as
 * safety-critical: the trigger event (EmergencyEvent) is immutable, the
 * lifecycle (EmergencyResponse) is a separate mutable record layered on top.
 */

export type EmergencyType = 'panic' | 'medical' | 'security_threat' | 'other';
export type EmergencyStatus = 'triggered' | 'acknowledged' | 'responding' | 'resolved';

export interface EmergencyEvent {
  id: string;
  tenantId: string;
  employeeId: string;
  siteId: string | null;
  shiftId: string | null;
  emergencyType: EmergencyType;
  latitude: number | null;
  longitude: number | null;
  accuracyMeters: number | null;
  triggeredAt: string;
}

export interface EmergencyResponse {
  id: string;
  tenantId: string;
  emergencyEventId: string;
  status: EmergencyStatus;
  acknowledgedBy: string | null;
  acknowledgedAt: string | null;
  respondingBy: string | null;
  respondingAt: string | null;
  resolvedBy: string | null;
  resolvedAt: string | null;
  resolutionReason: string | null;
  escalationLevel: number;
}

export interface ActiveEmergency {
  event: EmergencyEvent;
  response: EmergencyResponse;
}
