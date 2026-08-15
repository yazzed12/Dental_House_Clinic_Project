-- Phase 11B proposal only. Do not apply without explicit production approval.
BEGIN;

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS supabase_user_id uuid,
    ADD COLUMN IF NOT EXISTS personal_email text,
    ADD COLUMN IF NOT EXISTS approved_at timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS uq_users_supabase_user_id
    ON public.users (supabase_user_id)
    WHERE supabase_user_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_users_normalized_personal_email
    ON public.users (lower(btrim(personal_email)))
    WHERE personal_email IS NOT NULL;

DO $migration$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'fk_users_supabase_user_id'
          AND conrelid = 'public.users'::regclass
    ) THEN
        ALTER TABLE public.users
            ADD CONSTRAINT fk_users_supabase_user_id
            FOREIGN KEY (supabase_user_id)
            REFERENCES auth.users(id)
            ON DELETE SET NULL
            NOT VALID;
    END IF;
END
$migration$;

ALTER TABLE public.users
    VALIDATE CONSTRAINT fk_users_supabase_user_id;

COMMIT;
