-- S2 DRAFT ONLY. MOVE INTO THE NUMBERED MIGRATION SET ONLY AFTER APPROVAL.
-- This file has not been executed against any database.
BEGIN;

CREATE TABLE public.patient_care_team (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id uuid NOT NULL
        REFERENCES public.patients(id) ON DELETE RESTRICT,
    doctor_id uuid NOT NULL
        REFERENCES public.users(id) ON DELETE RESTRICT,
    status text NOT NULL,
    relationship_kind text NOT NULL,
    source_type text NOT NULL,
    source_appointment_id uuid NULL
        REFERENCES public.appointments(id) ON DELETE SET NULL,
    assigned_by uuid NOT NULL
        REFERENCES public.users(id) ON DELETE RESTRICT,
    starts_at timestamptz NOT NULL DEFAULT now(),
    established_at timestamptz NULL,
    ended_at timestamptz NULL,
    ended_by uuid NULL
        REFERENCES public.users(id) ON DELETE RESTRICT,
    end_reason text NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT patient_care_team_status_check
        CHECK (status IN ('scheduled', 'active', 'ended', 'revoked')),
    CONSTRAINT patient_care_team_kind_check
        CHECK (relationship_kind IN ('primary', 'treating', 'consulting')),
    CONSTRAINT patient_care_team_source_check
        CHECK (source_type IN ('admin', 'appointment', 'consultation', 'migration')),
    CONSTRAINT patient_care_team_interval_check
        CHECK (ended_at IS NULL OR ended_at >= starts_at),
    CONSTRAINT patient_care_team_established_check
        CHECK (established_at IS NULL OR established_at >= starts_at),
    CONSTRAINT patient_care_team_closed_state_check
        CHECK (
            (status IN ('scheduled', 'active') AND ended_at IS NULL AND ended_by IS NULL)
            OR
            (status IN ('ended', 'revoked') AND ended_at IS NOT NULL AND ended_by IS NOT NULL)
        ),
    CONSTRAINT patient_care_team_appointment_source_check
        CHECK (
            (source_type = 'appointment' AND source_appointment_id IS NOT NULL)
            OR source_type <> 'appointment'
        )
);

CREATE UNIQUE INDEX uq_patient_care_team_open_doctor_patient
    ON public.patient_care_team (patient_id, doctor_id)
    WHERE status IN ('scheduled', 'active');

CREATE UNIQUE INDEX uq_patient_care_team_open_primary
    ON public.patient_care_team (patient_id)
    WHERE status IN ('scheduled', 'active')
      AND relationship_kind = 'primary';

CREATE UNIQUE INDEX uq_patient_care_team_appointment_source
    ON public.patient_care_team (patient_id, doctor_id, source_appointment_id)
    WHERE source_appointment_id IS NOT NULL;

CREATE INDEX ix_patient_care_team_doctor_access
    ON public.patient_care_team (doctor_id, patient_id, status);

CREATE INDEX ix_patient_care_team_patient_history
    ON public.patient_care_team (patient_id, starts_at, ended_at);

COMMENT ON TABLE public.patient_care_team IS
    'Durable, audited doctor-patient treatment relationships. Direct browser writes are forbidden.';
COMMENT ON COLUMN public.patient_care_team.source_appointment_id IS
    'Trusted only when populated by an authorized scheduling/admin RPC from a non-null appointments.doctor_id.';

-- Final grants belong in the later approved RLS migration. The table is not
-- browser-writable; assignment identity and assigned_by must be derived by a
-- trusted RPC/server workflow, never accepted as client authority.
REVOKE INSERT, UPDATE, DELETE ON public.patient_care_team FROM anon, authenticated;

COMMIT;
