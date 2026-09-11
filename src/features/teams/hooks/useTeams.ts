import { useCallback, useEffect, useState } from 'react';
import { teamService } from '@/features/teams/services/teamService';
import type { Team, TeamMember } from '@/features/teams/types/team.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

export interface UseTeamsResult {
  teams: Team[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useTeams(tenantId: string | undefined): UseTeamsResult {
  const [teams, setTeams] = useState<Team[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!tenantId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setTeams(await teamService.getTeams(tenantId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load teams.'));
    } finally {
      setIsLoading(false);
    }
  }, [tenantId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { teams, isLoading, error, refetch: load };
}

export interface UseTeamResult {
  team: Team | null;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useTeam(teamId: string | undefined): UseTeamResult {
  const [team, setTeam] = useState<Team | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!teamId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setTeam(await teamService.getTeam(teamId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load team.'));
    } finally {
      setIsLoading(false);
    }
  }, [teamId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { team, isLoading, error, refetch: load };
}

export interface UseTeamMembersResult {
  members: TeamMember[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useTeamMembers(teamId: string | undefined): UseTeamMembersResult {
  const [members, setMembers] = useState<TeamMember[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!teamId) {
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    setError(null);
    try {
      setMembers(await teamService.getTeamMembers(teamId));
    } catch (err) {
      setError(getDbErrorMessage(err, 'Failed to load team members.'));
    } finally {
      setIsLoading(false);
    }
  }, [teamId]);

  useEffect(() => {
    void load();
  }, [load]);

  return { members, isLoading, error, refetch: load };
}

export interface UseTeamsForEmployeeResult {
  teams: Team[];
  isLoading: boolean;
  error: string | null;
}

export function useTeamsForEmployee(employeeId: string | undefined): UseTeamsForEmployeeResult {
  const [teams, setTeams] = useState<Team[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!employeeId) {
      setIsLoading(false);
      return;
    }
    let cancelled = false;
    setIsLoading(true);
    teamService
      .getTeamsForEmployee(employeeId)
      .then((result) => {
        if (!cancelled) setTeams(result);
      })
      .catch((err: unknown) => {
        if (!cancelled) setError(getDbErrorMessage(err, 'Failed to load teams.'));
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [employeeId]);

  return { teams, isLoading, error };
}
