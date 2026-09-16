import { describe, expect, it } from 'vitest';
import { matchIntent } from '@/features/intelligence/utils/matchIntent';

describe('matchIntent', () => {
  it('matches understaffed-site questions', () => {
    expect(matchIntent('Which sites are understaffed?')).toBe('understaffed_sites');
    expect(matchIntent('Do we have a staffing gap at Site A?')).toBe('understaffed_sites');
  });

  it('matches absence questions', () => {
    expect(matchIntent("Who's absent right now?")).toBe('absent_employees');
    expect(matchIntent('Did anyone no show today?')).toBe('absent_employees');
  });

  it('matches expiring-qualification questions', () => {
    expect(matchIntent('Any certifications expiring soon?')).toBe('expiring_qualifications');
    expect(matchIntent('Whose PSIRA license is expiring?')).toBe('expiring_qualifications');
  });

  it('matches SLA questions', () => {
    expect(matchIntent('Which contracts are breaching SLA?')).toBe('declining_sla');
  });

  it('matches overtime questions', () => {
    expect(matchIntent('Who has overtime spikes this month?')).toBe('overtime_spikes');
  });

  it('matches incident-hotspot questions', () => {
    expect(matchIntent('Which sites have the most incidents?')).toBe('incident_hotspots');
    expect(matchIntent('Show me our incident hotspots')).toBe('incident_hotspots');
  });

  it('is case-insensitive', () => {
    expect(matchIntent('WHICH SITES ARE UNDERSTAFFED')).toBe('understaffed_sites');
  });

  it('returns null for a question no whitelisted tool answers', () => {
    expect(matchIntent('What is the weather today?')).toBeNull();
    expect(matchIntent('Write me a poem about security guards')).toBeNull();
    expect(matchIntent('')).toBeNull();
  });

  it('never routes to arbitrary SQL or free text — every match is one of the six whitelisted tool keys', () => {
    const WHITELISTED = new Set(['understaffed_sites', 'absent_employees', 'expiring_qualifications', 'declining_sla', 'overtime_spikes', 'incident_hotspots']);
    const sampleQueries = ['understaffed', 'absent', 'expiring', 'sla breach', 'overtime', 'incident hotspot'];
    for (const query of sampleQueries) {
      const result = matchIntent(query);
      expect(result === null || WHITELISTED.has(result)).toBe(true);
    }
  });
});
