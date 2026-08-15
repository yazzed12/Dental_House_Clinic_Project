-- C6 Symptoms & Findings Supabase vertical slice.
-- No default data is seeded here; production preflight determines whether a
-- separate explicit seed migration is necessary.

BEGIN;

DROP POLICY IF EXISTS "Allow all" ON public.symptoms;
DROP POLICY IF EXISTS "Allow clinic staff full access" ON public.symptoms;
DROP POLICY IF EXISTS "Allow clinic staff to read symptoms" ON public.symptoms;
DROP POLICY IF EXISTS "Allow clinic staff to manage symptoms" ON public.symptoms;
DROP POLICY IF EXISTS "Allow initial data migration" ON public.symptoms;

REVOKE ALL ON TABLE public.symptoms FROM PUBLIC;
REVOKE ALL ON TABLE public.symptoms FROM anon;
REVOKE ALL ON TABLE public.symptoms FROM authenticated;
ALTER TABLE public.symptoms ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.list_active_symptoms()
RETURNS TABLE (
    id text,
    name text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_caller_id uuid;
BEGIN
    SELECT app_user.id
      INTO v_caller_id
      FROM public.users AS app_user
     WHERE app_user.supabase_user_id = auth.uid()
       AND app_user.is_active = true
       AND app_user.approved_at IS NOT NULL
       AND app_user.role IN ('doctor', 'admin')
     LIMIT 1;

    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'SYMPTOM_AUTHORIZATION_DENIED'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        symptom.id::text,
        btrim(symptom.name)::text
    FROM public.symptoms AS symptom
    WHERE symptom.is_active <> 0
      AND symptom.name IS NOT NULL
      AND btrim(symptom.name) <> ''
    ORDER BY lower(btrim(symptom.name)), symptom.id::text;
END
$function$;

CREATE OR REPLACE FUNCTION public.create_or_reactivate_symptom(
    p_name text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_caller_id uuid;
    v_trimmed_name text := btrim(p_name);
    v_normalized_name text;
    v_symptom_id text;
    v_symptom_name text;
    v_is_active integer;
BEGIN
    SELECT app_user.id
      INTO v_caller_id
      FROM public.users AS app_user
     WHERE app_user.supabase_user_id = auth.uid()
       AND app_user.is_active = true
       AND app_user.approved_at IS NOT NULL
       AND app_user.role IN ('doctor', 'admin')
     LIMIT 1;

    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'SYMPTOM_AUTHORIZATION_DENIED'
            USING ERRCODE = '42501';
    END IF;

    IF v_trimmed_name IS NULL OR v_trimmed_name = '' THEN
        RAISE EXCEPTION 'SYMPTOM_NAME_REQUIRED'
            USING ERRCODE = '22023';
    END IF;

    v_normalized_name := lower(v_trimmed_name);

    -- Serialize all compliant writers for the same logical name without adding
    -- an unverified/destructive uniqueness constraint to existing production data.
    PERFORM pg_advisory_xact_lock(hashtextextended(v_normalized_name, 0));

    SELECT
        symptom.id::text,
        symptom.name,
        symptom.is_active
      INTO v_symptom_id, v_symptom_name, v_is_active
      FROM public.symptoms AS symptom
     WHERE lower(btrim(symptom.name)) = v_normalized_name
     ORDER BY
           CASE WHEN symptom.is_active <> 0 THEN 0 ELSE 1 END,
           symptom.id::text
     LIMIT 1
     FOR UPDATE;

    IF v_symptom_id IS NOT NULL THEN
        IF v_is_active = 0 OR v_is_active IS NULL THEN
            UPDATE public.symptoms AS symptom
               SET is_active = 1
             WHERE symptom.id::text = v_symptom_id
             RETURNING btrim(symptom.name) INTO v_symptom_name;
        END IF;

        RETURN jsonb_build_object(
            'id', v_symptom_id,
            'name', btrim(v_symptom_name)
        );
    END IF;

    INSERT INTO public.symptoms AS symptom (
        name,
        created_by,
        is_active
    ) VALUES (
        v_trimmed_name,
        v_caller_id,
        1
    )
    RETURNING symptom.id::text, btrim(symptom.name)
         INTO v_symptom_id, v_symptom_name;

    RETURN jsonb_build_object(
        'id', v_symptom_id,
        'name', v_symptom_name
    );
END
$function$;

REVOKE ALL ON FUNCTION public.list_active_symptoms() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.list_active_symptoms() FROM anon;
GRANT EXECUTE ON FUNCTION public.list_active_symptoms() TO authenticated;

REVOKE ALL ON FUNCTION public.create_or_reactivate_symptom(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_or_reactivate_symptom(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_or_reactivate_symptom(text) TO authenticated;

COMMIT;
