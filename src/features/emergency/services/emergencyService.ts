import { supabase } from '@/lib/supabase';
import type { EmergencyEventRow, EmergencyResponseRow } from '@/lib/dbTypes';
import type { EmergencyEvent, EmergencyResponse, EmergencyType, ActiveEmergency } from '@/features/emergency/types/emergency.types';
import type { DeviceLocation } from '@/features/attendance/types/attendance.types';

function toEmergencyEvent(row: EmergencyEventRow): EmergencyEvent {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    employeeId: row.employee_id,
    siteId: row.site_id,
    shiftId: row.shift_id,
    emergencyType: row.emergency_type,
    latitude: row.latitude,
    longitude: row.longitude,
    accuracyMeters: row.accuracy_meters,
    triggeredAt: row.triggered_at,
  };
}

function toEmergencyResponse(row: EmergencyResponseRow): EmergencyResponse {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    emergencyEventId: row.emergency_event_id,
    status: row.status,
    acknowledgedBy: row.acknowledged_by,
    acknowledgedAt: row.acknowledged_at,
    respondingBy: row.responding_by,
    respondingAt: row.responding_at,
    resolvedBy: row.resolved_by,
    resolvedAt: row.resolved_at,
    resolutionReason: row.resolution_reason,
    escalationLevel: row.escalation_level,
  };
}

/**
 * `location` is `null` when the device couldn't produce a read — the
 * emergency is still triggered; a panic button must never be blocked on a
 * GPS fix that may never arrive. The server records whatever location
 * evidence is available, nothing more.
 */
async function triggerEmergency(location: DeviceLocation | null, emergencyType: EmergencyType = 'panic'): Promise<EmergencyEvent> {
  const { data, error } = await supabase.rpc('trigger_emergency', {
    p_latitude: location?.latitude,
    p_longitude: location?.longitude,
    p_accuracy_meters: location?.accuracyMeters ?? undefined,
    p_emergency_type: emergencyType,
  });
  if (error) throw error;
  return toEmergencyEvent(data);
}

/** Every unresolved emergency across the tenant, most recent first — RLS restricts this to the operations-management tier. */
async function getActiveEmergencies(tenantId: string): Promise<ActiveEmergency[]> {
  const { data: responses, error: responsesError } = await supabase
    .from('emergency_responses')
    .select('*')
    .eq('tenant_id', tenantId)
    .neq('status', 'resolved')
    .order('created_at', { ascending: false });
  if (responsesError) throw responsesError;
  if (responses.length === 0) return [];

  const eventIds = responses.map((response) => response.emergency_event_id);
  const { data: events, error: eventsError } = await supabase.from('emergency_events').select('*').in('id', eventIds);
  if (eventsError) throw eventsError;

  const eventsById = new Map(events.map((event) => [event.id, toEmergencyEvent(event)]));
  return responses.flatMap((response) => {
    const event = eventsById.get(response.emergency_event_id);
    return event ? [{ event, response: toEmergencyResponse(response) }] : [];
  });
}

async function acknowledgeEmergency(emergencyEventId: string): Promise<EmergencyResponse> {
  const { data, error } = await supabase.rpc('acknowledge_emergency', { p_emergency_event_id: emergencyEventId });
  if (error) throw error;
  return toEmergencyResponse(data);
}

async function respondToEmergency(emergencyEventId: string, notes?: string): Promise<EmergencyResponse> {
  const { data, error } = await supabase.rpc('respond_to_emergency', { p_emergency_event_id: emergencyEventId, p_notes: notes });
  if (error) throw error;
  return toEmergencyResponse(data);
}

async function resolveEmergency(emergencyEventId: string, resolutionReason: string): Promise<EmergencyResponse> {
  const { data, error } = await supabase.rpc('resolve_emergency', { p_emergency_event_id: emergencyEventId, p_resolution_reason: resolutionReason });
  if (error) throw error;
  return toEmergencyResponse(data);
}

export const emergencyService = {
  triggerEmergency,
  getActiveEmergencies,
  acknowledgeEmergency,
  respondToEmergency,
  resolveEmergency,
};
