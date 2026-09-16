import { useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { FullScreenSpinner } from '@/components/ui/FullScreenSpinner';
import { FullScreenNotice } from '@/components/ui/FullScreenNotice';
import { Button } from '@/components/ui/Button';
import { TextField } from '@/components/ui/TextField';
import { ErrorAlert } from '@/components/ui/ErrorAlert';
import { StatusBadge, type StatusTone } from '@/components/ui/StatusBadge';
import { usePermissions } from '@/hooks/usePermissions';
import { useSiteSurvey } from '@/features/siteSurveys/hooks/useSiteSurveys';
import { useClient } from '@/features/orgStructure/hooks/useClients';
import { siteSurveyService } from '@/features/siteSurveys/services/siteSurveyService';
import type { SiteSurveyStatus, UpdateSiteSurveyInput } from '@/features/siteSurveys/types/siteSurvey.types';
import { getDbErrorMessage } from '@/lib/dbErrors';

const STATUS_TONE: Record<SiteSurveyStatus, StatusTone> = {
  draft: 'neutral',
  completed: 'info',
  converted: 'success',
};

interface FormState {
  address: string;
  buildingType: string;
  floorCount: string;
  approxAreaSqm: string;
  officeCount: string;
  bathroomCount: string;
  kitchenCount: string;
  entranceCount: string;
  commonAreaCount: string;
  windowCount: string;
  floorTypes: string;
  specialSurfaces: string;
  operatingHours: string;
  accessRestrictions: string;
  requiredServices: string;
  equipmentRequirements: string;
  consumableRequirements: string;
  risks: string;
  specialInstructions: string;
  notes: string;
}

const EMPTY_FORM: FormState = {
  address: '',
  buildingType: '',
  floorCount: '',
  approxAreaSqm: '',
  officeCount: '',
  bathroomCount: '',
  kitchenCount: '',
  entranceCount: '',
  commonAreaCount: '',
  windowCount: '',
  floorTypes: '',
  specialSurfaces: '',
  operatingHours: '',
  accessRestrictions: '',
  requiredServices: '',
  equipmentRequirements: '',
  consumableRequirements: '',
  risks: '',
  specialInstructions: '',
  notes: '',
};

export function SiteSurveyDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { can } = usePermissions();
  const canManage = can('org_structure.manage');
  const { survey, isLoading, error, refetch } = useSiteSurvey(id);
  const { client } = useClient(survey?.clientId);

  const [form, setForm] = useState<FormState>(EMPTY_FORM);
  const [isSaving, setIsSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [convertError, setConvertError] = useState<string | null>(null);
  const [isConverting, setIsConverting] = useState(false);

  useEffect(() => {
    if (!survey) return;
    setForm({
      address: survey.address ?? '',
      buildingType: survey.buildingType ?? '',
      floorCount: survey.floorCount?.toString() ?? '',
      approxAreaSqm: survey.approxAreaSqm?.toString() ?? '',
      officeCount: survey.officeCount?.toString() ?? '',
      bathroomCount: survey.bathroomCount?.toString() ?? '',
      kitchenCount: survey.kitchenCount?.toString() ?? '',
      entranceCount: survey.entranceCount?.toString() ?? '',
      commonAreaCount: survey.commonAreaCount?.toString() ?? '',
      windowCount: survey.windowCount?.toString() ?? '',
      floorTypes: survey.floorTypes ?? '',
      specialSurfaces: survey.specialSurfaces ?? '',
      operatingHours: survey.operatingHours ?? '',
      accessRestrictions: survey.accessRestrictions ?? '',
      requiredServices: survey.requiredServices ?? '',
      equipmentRequirements: survey.equipmentRequirements ?? '',
      consumableRequirements: survey.consumableRequirements ?? '',
      risks: survey.risks ?? '',
      specialInstructions: survey.specialInstructions ?? '',
      notes: survey.notes ?? '',
    });
  }, [survey]);

  if (isLoading) return <FullScreenSpinner label="Loading site survey…" />;
  if (error) return <FullScreenNotice title="Something went wrong" message={error} />;
  if (!survey) {
    return (
      <FullScreenNotice
        title="Site survey not found"
        message="This survey doesn't exist, or you don't have access to view it."
        action={
          <Link to="/site-surveys" className="focus-ring self-start rounded text-sm font-medium text-brand-600 hover:underline">
            Back to Site Surveys
          </Link>
        }
      />
    );
  }

  const toNumberOrNull = (value: string) => (value.trim() === '' ? null : Number(value));

  const handleSave = async () => {
    setIsSaving(true);
    setSaveError(null);
    try {
      const payload: UpdateSiteSurveyInput = {
        address: form.address.trim() || null,
        buildingType: form.buildingType.trim() || null,
        floorCount: toNumberOrNull(form.floorCount),
        approxAreaSqm: toNumberOrNull(form.approxAreaSqm),
        officeCount: toNumberOrNull(form.officeCount),
        bathroomCount: toNumberOrNull(form.bathroomCount),
        kitchenCount: toNumberOrNull(form.kitchenCount),
        entranceCount: toNumberOrNull(form.entranceCount),
        commonAreaCount: toNumberOrNull(form.commonAreaCount),
        windowCount: toNumberOrNull(form.windowCount),
        floorTypes: form.floorTypes.trim() || null,
        specialSurfaces: form.specialSurfaces.trim() || null,
        operatingHours: form.operatingHours.trim() || null,
        accessRestrictions: form.accessRestrictions.trim() || null,
        requiredServices: form.requiredServices.trim() || null,
        equipmentRequirements: form.equipmentRequirements.trim() || null,
        consumableRequirements: form.consumableRequirements.trim() || null,
        risks: form.risks.trim() || null,
        specialInstructions: form.specialInstructions.trim() || null,
        notes: form.notes.trim() || null,
      };
      await siteSurveyService.updateSurvey(survey.id, payload);
      await refetch();
    } catch (err) {
      setSaveError(getDbErrorMessage(err, 'Failed to save the site survey.'));
    } finally {
      setIsSaving(false);
    }
  };

  const handleMarkCompleted = async () => {
    setSaveError(null);
    try {
      await siteSurveyService.updateSurvey(survey.id, { status: 'completed' });
      await refetch();
    } catch (err) {
      setSaveError(getDbErrorMessage(err, 'Failed to mark the survey completed.'));
    }
  };

  const handleConvert = async () => {
    setIsConverting(true);
    setConvertError(null);
    try {
      const site = await siteSurveyService.convertToSite(survey.id);
      await refetch();
      navigate(`/sites/${site.id}`);
    } catch (err) {
      setConvertError(getDbErrorMessage(err, 'Failed to convert this survey to a site.'));
    } finally {
      setIsConverting(false);
    }
  };

  const field = (key: keyof FormState, label: string, type: 'text' | 'number' = 'text') => (
    <TextField label={label} type={type} value={form[key]} onChange={(event) => setForm((prev) => ({ ...prev, [key]: event.target.value }))} disabled={!canManage} />
  );

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-6 px-4 py-8 sm:px-6">
      <button type="button" onClick={() => navigate('/site-surveys')} className="focus-ring self-start rounded text-sm font-medium text-content-secondary hover:text-content-primary">
        ← Back to Site Surveys
      </button>

      <div className="rounded-card border border-border bg-surface-raised p-6 shadow-card dark:shadow-card-dark">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h1 className="text-xl font-bold text-content-primary">{survey.prospectiveSiteName}</h1>
            <p className="text-sm text-content-secondary">
              {client ? (
                <Link to={`/clients/${client.id}`} className="text-brand-600 hover:underline">
                  {client.name}
                </Link>
              ) : (
                'No client'
              )}
            </p>
          </div>
          <StatusBadge label={survey.status} tone={STATUS_TONE[survey.status]} />
        </div>

        {survey.siteId && (
          <p className="mt-4 rounded-lg border border-success-500/30 bg-success-500/10 px-3.5 py-2.5 text-sm font-medium text-success-600">
            Converted to a site.{' '}
            <Link to={`/sites/${survey.siteId}`} className="underline">
              View site
            </Link>
          </p>
        )}

        {canManage && survey.status === 'draft' && (
          <div className="mt-4 flex gap-2 border-t border-border pt-4">
            <Button variant="secondary" onClick={() => void handleMarkCompleted()}>
              Mark completed
            </Button>
          </div>
        )}

        {canManage && survey.status !== 'draft' && !survey.siteId && (
          <div className="mt-4 border-t border-border pt-4">
            <ErrorAlert message={convertError} />
            <Button onClick={() => void handleConvert()} isLoading={isConverting}>
              Convert to site
            </Button>
          </div>
        )}
      </div>

      <section className="flex flex-col gap-3">
        <h2 className="text-base font-semibold text-content-primary">Building details</h2>
        <ErrorAlert message={saveError} />
        <div className="grid grid-cols-1 gap-4 rounded-card border border-border bg-surface-raised p-4 sm:grid-cols-2">
          {field('address', 'Address')}
          {field('buildingType', 'Building type')}
          {field('floorCount', 'Floors', 'number')}
          {field('approxAreaSqm', 'Approx. area (m²)', 'number')}
          {field('officeCount', 'Offices', 'number')}
          {field('bathroomCount', 'Bathrooms', 'number')}
          {field('kitchenCount', 'Kitchens', 'number')}
          {field('entranceCount', 'Entrances', 'number')}
          {field('commonAreaCount', 'Common areas', 'number')}
          {field('windowCount', 'Windows', 'number')}
          {field('floorTypes', 'Floor types')}
          {field('operatingHours', 'Operating hours')}
        </div>
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-base font-semibold text-content-primary">Requirements &amp; notes</h2>
        <div className="grid grid-cols-1 gap-4 rounded-card border border-border bg-surface-raised p-4">
          <label className="flex flex-col gap-1.5 text-sm">
            <span className="font-medium text-content-primary">Special surfaces</span>
            <textarea rows={2} value={form.specialSurfaces} onChange={(event) => setForm((prev) => ({ ...prev, specialSurfaces: event.target.value }))} disabled={!canManage} className="focus-ring rounded-lg border border-border-strong bg-surface-raised px-3.5 py-2.5 text-content-primary disabled:opacity-60" />
          </label>
          <label className="flex flex-col gap-1.5 text-sm">
            <span className="font-medium text-content-primary">Access restrictions</span>
            <textarea rows={2} value={form.accessRestrictions} onChange={(event) => setForm((prev) => ({ ...prev, accessRestrictions: event.target.value }))} disabled={!canManage} className="focus-ring rounded-lg border border-border-strong bg-surface-raised px-3.5 py-2.5 text-content-primary disabled:opacity-60" />
          </label>
          <label className="flex flex-col gap-1.5 text-sm">
            <span className="font-medium text-content-primary">Required services</span>
            <textarea rows={2} value={form.requiredServices} onChange={(event) => setForm((prev) => ({ ...prev, requiredServices: event.target.value }))} disabled={!canManage} className="focus-ring rounded-lg border border-border-strong bg-surface-raised px-3.5 py-2.5 text-content-primary disabled:opacity-60" />
          </label>
          <label className="flex flex-col gap-1.5 text-sm">
            <span className="font-medium text-content-primary">Equipment requirements</span>
            <textarea rows={2} value={form.equipmentRequirements} onChange={(event) => setForm((prev) => ({ ...prev, equipmentRequirements: event.target.value }))} disabled={!canManage} className="focus-ring rounded-lg border border-border-strong bg-surface-raised px-3.5 py-2.5 text-content-primary disabled:opacity-60" />
          </label>
          <label className="flex flex-col gap-1.5 text-sm">
            <span className="font-medium text-content-primary">Consumable requirements</span>
            <textarea rows={2} value={form.consumableRequirements} onChange={(event) => setForm((prev) => ({ ...prev, consumableRequirements: event.target.value }))} disabled={!canManage} className="focus-ring rounded-lg border border-border-strong bg-surface-raised px-3.5 py-2.5 text-content-primary disabled:opacity-60" />
          </label>
          <label className="flex flex-col gap-1.5 text-sm">
            <span className="font-medium text-content-primary">Risks</span>
            <textarea rows={2} value={form.risks} onChange={(event) => setForm((prev) => ({ ...prev, risks: event.target.value }))} disabled={!canManage} className="focus-ring rounded-lg border border-border-strong bg-surface-raised px-3.5 py-2.5 text-content-primary disabled:opacity-60" />
          </label>
          <label className="flex flex-col gap-1.5 text-sm">
            <span className="font-medium text-content-primary">Special instructions</span>
            <textarea rows={2} value={form.specialInstructions} onChange={(event) => setForm((prev) => ({ ...prev, specialInstructions: event.target.value }))} disabled={!canManage} className="focus-ring rounded-lg border border-border-strong bg-surface-raised px-3.5 py-2.5 text-content-primary disabled:opacity-60" />
          </label>
          <label className="flex flex-col gap-1.5 text-sm">
            <span className="font-medium text-content-primary">Notes</span>
            <textarea rows={2} value={form.notes} onChange={(event) => setForm((prev) => ({ ...prev, notes: event.target.value }))} disabled={!canManage} className="focus-ring rounded-lg border border-border-strong bg-surface-raised px-3.5 py-2.5 text-content-primary disabled:opacity-60" />
          </label>
        </div>
        {canManage && (
          <Button onClick={() => void handleSave()} isLoading={isSaving}>
            Save survey
          </Button>
        )}
      </section>
    </div>
  );
}
