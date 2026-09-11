import { useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { teamService } from '@/features/teams/services/teamService';
import { employeeService } from '@/features/employees/services/employeeService';
import type { EmployeeCandidate } from '@/features/employees/services/employeeService';
import { getDbErrorMessage } from '@/lib/dbErrors';
import { teamSchema, teamDefaultValues, type TeamFormValues } from '@/features/teams/schemas/teamSchema';
import type { Team } from '@/features/teams/types/team.types';
import type { Site } from '@/features/orgStructure/types/orgStructure.types';

export interface TeamFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  tenantId: string;
  team?: Team | null;
  sites: Site[];
  onSaved: (team: Team) => void;
}

export function TeamFormModal({ isOpen, onClose, tenantId, team, sites, onSaved }: TeamFormModalProps) {
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [leadSearch, setLeadSearch] = useState('');
  const [leadCandidates, setLeadCandidates] = useState<EmployeeCandidate[]>([]);
  const [selectedLead, setSelectedLead] = useState<EmployeeCandidate | null>(null);
  const isEditing = Boolean(team);

  const {
    register,
    handleSubmit,
    reset,
    setValue,
    watch,
    formState: { errors, isSubmitting },
  } = useForm<TeamFormValues>({ resolver: zodResolver(teamSchema), defaultValues: teamDefaultValues });

  const leadEmployeeId = watch('leadEmployeeId');

  useEffect(() => {
    if (!isOpen) return;
    reset(
      team
        ? { name: team.name, siteId: team.siteId ?? '', leadEmployeeId: team.leadEmployeeId ?? '' }
        : teamDefaultValues,
    );
    setLeadSearch('');
    setSelectedLead(null);
    setSubmitError(null);
  }, [isOpen, team, reset]);

  useEffect(() => {
    if (!isOpen || !team?.leadEmployeeId) return;
    let cancelled = false;
    void employeeService.getEmployee(team.leadEmployeeId).then((result) => {
      if (!cancelled && result) setSelectedLead({ id: result.id, firstName: result.firstName, lastName: result.lastName });
    });
    return () => {
      cancelled = true;
    };
  }, [isOpen, team?.leadEmployeeId]);

  useEffect(() => {
    if (!isOpen) return;
    let cancelled = false;
    void employeeService.searchEmployeeCandidates(tenantId, leadSearch).then((results) => {
      if (!cancelled) setLeadCandidates(results);
    });
    return () => {
      cancelled = true;
    };
  }, [isOpen, tenantId, leadSearch]);

  const onValid = async (values: TeamFormValues) => {
    setSubmitError(null);
    try {
      const payload = {
        name: values.name,
        siteId: values.siteId?.trim() || null,
        leadEmployeeId: values.leadEmployeeId?.trim() || null,
      };
      const saved = team
        ? await teamService.updateTeam(team.id, payload)
        : await teamService.createTeam(tenantId, payload);
      onSaved(saved);
      onClose();
    } catch (error) {
      setSubmitError(getDbErrorMessage(error, 'Failed to save team.'));
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={isEditing ? 'Edit team' : 'Add team'}
      footer={
        <Button type="submit" form="team-form" isLoading={isSubmitting}>
          {isSubmitting ? 'Saving…' : 'Save'}
        </Button>
      }
    >
      <form noValidate id="team-form" onSubmit={handleSubmit(onValid)} className="flex flex-col gap-4">
        {submitError && (
          <div
            role="alert"
            className="rounded-lg border border-danger-500/30 bg-danger-50 px-3.5 py-2.5 text-sm font-medium text-danger-600"
          >
            {submitError}
          </div>
        )}

        <TextField label="Team name" required placeholder="Team A" error={errors.name?.message} {...register('name')} />

        <div>
          <label htmlFor="team-site" className="mb-1.5 block text-sm font-medium text-content-primary">
            Site
          </label>
          <select
            id="team-site"
            className="focus-ring h-11 w-full rounded-lg border border-border-strong bg-surface-raised px-3.5 text-sm text-content-primary"
            {...register('siteId')}
          >
            <option value="">Unassigned</option>
            {sites.map((site) => (
              <option key={site.id} value={site.id}>
                {site.name}
              </option>
            ))}
          </select>
        </div>

        <div>
          <TextField
            label="Team lead"
            hint={selectedLead ? `Selected: ${selectedLead.firstName} ${selectedLead.lastName}` : 'Search by name…'}
            placeholder="Search by name…"
            value={leadSearch}
            onChange={(event) => setLeadSearch(event.target.value)}
          />
          <div className="mt-2 flex max-h-32 flex-col gap-1 overflow-y-auto">
            <button
              type="button"
              onClick={() => {
                setValue('leadEmployeeId', '', { shouldValidate: true });
                setSelectedLead(null);
              }}
              className={`focus-ring rounded-lg border px-3 py-2 text-left text-sm ${
                !leadEmployeeId
                  ? 'border-brand-500 bg-brand-50 dark:bg-brand-500/10'
                  : 'border-border-strong bg-surface-raised hover:bg-surface-sunken'
              }`}
            >
              No lead
            </button>
            {leadCandidates.map((candidate) => (
              <button
                key={candidate.id}
                type="button"
                onClick={() => {
                  setValue('leadEmployeeId', candidate.id, { shouldValidate: true });
                  setSelectedLead(candidate);
                }}
                className={`focus-ring rounded-lg border px-3 py-2 text-left text-sm ${
                  leadEmployeeId === candidate.id
                    ? 'border-brand-500 bg-brand-50 dark:bg-brand-500/10'
                    : 'border-border-strong bg-surface-raised hover:bg-surface-sunken'
                }`}
              >
                {candidate.firstName} {candidate.lastName}
              </button>
            ))}
          </div>
        </div>
      </form>
    </Modal>
  );
}
