-- Migration 022: clinic-wide Lab Management foundation.
-- Lab data is RPC-only and intentionally isolated from medical reports/billing.
BEGIN;

DO $precondition$
BEGIN
    IF to_regclass('public.consultations') IS NULL
       OR to_regclass('public.patients') IS NULL
       OR to_regclass('public.users') IS NULL
       OR to_regclass('public.appointments') IS NULL THEN
        RAISE EXCEPTION 'LAB_FOUNDATION_REQUIRED_RELATION_MISSING';
    END IF;
    IF to_regclass('public.labs') IS NOT NULL
       OR to_regclass('public.lab_products') IS NOT NULL
       OR to_regclass('public.consultation_lab_items') IS NOT NULL
       OR EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='consultations' AND column_name='lab_note') THEN
        RAISE EXCEPTION 'LAB_FOUNDATION_CONFLICTING_SCHEMA';
    END IF;
END
$precondition$;

CREATE TABLE public.labs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    created_by uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT labs_created_by_fk FOREIGN KEY (created_by)
        REFERENCES public.users(id) ON DELETE RESTRICT,
    CONSTRAINT labs_name_nonempty_ck CHECK (btrim(name) <> ''),
    CONSTRAINT labs_name_length_ck CHECK (char_length(btrim(name)) <= 200)
);

CREATE UNIQUE INDEX labs_normalized_name_uq
    ON public.labs (lower(btrim(name)));
CREATE INDEX labs_active_name_idx
    ON public.labs (lower(btrim(name)), id) WHERE is_active;
CREATE INDEX labs_created_by_idx
    ON public.labs (created_by);

CREATE TABLE public.lab_products (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    lab_id uuid NOT NULL,
    name text NOT NULL,
    current_price numeric(12,2) NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT lab_products_lab_fk FOREIGN KEY (lab_id)
        REFERENCES public.labs(id) ON DELETE RESTRICT,
    CONSTRAINT lab_products_name_nonempty_ck CHECK (btrim(name) <> ''),
    CONSTRAINT lab_products_name_length_ck CHECK (char_length(btrim(name)) <= 200),
    CONSTRAINT lab_products_price_ck CHECK (current_price >= 0)
);

CREATE UNIQUE INDEX lab_products_lab_normalized_name_uq
    ON public.lab_products (lab_id, lower(btrim(name)));
CREATE INDEX lab_products_active_catalog_idx
    ON public.lab_products (lab_id, lower(btrim(name)), id) WHERE is_active;

CREATE TABLE public.consultation_lab_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    consultation_id uuid NOT NULL,
    patient_id uuid NOT NULL,
    doctor_id uuid NOT NULL,
    lab_id uuid NOT NULL,
    lab_product_id uuid NOT NULL,
    lab_name_snapshot text NOT NULL,
    product_name_snapshot text NOT NULL,
    unit_price_snapshot numeric(12,2) NOT NULL,
    quantity integer NOT NULL,
    total_amount numeric(15,2)
        GENERATED ALWAYS AS ((unit_price_snapshot * quantity)::numeric(15,2)) STORED,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT consultation_lab_items_consultation_fk FOREIGN KEY (consultation_id)
        REFERENCES public.consultations(id) ON DELETE RESTRICT,
    CONSTRAINT consultation_lab_items_patient_fk FOREIGN KEY (patient_id)
        REFERENCES public.patients(id) ON DELETE RESTRICT,
    CONSTRAINT consultation_lab_items_doctor_fk FOREIGN KEY (doctor_id)
        REFERENCES public.users(id) ON DELETE RESTRICT,
    CONSTRAINT consultation_lab_items_lab_fk FOREIGN KEY (lab_id)
        REFERENCES public.labs(id) ON DELETE RESTRICT,
    CONSTRAINT consultation_lab_items_product_fk FOREIGN KEY (lab_product_id)
        REFERENCES public.lab_products(id) ON DELETE RESTRICT,
    CONSTRAINT consultation_lab_items_lab_name_ck CHECK (btrim(lab_name_snapshot) <> ''),
    CONSTRAINT consultation_lab_items_product_name_ck CHECK (btrim(product_name_snapshot) <> ''),
    CONSTRAINT consultation_lab_items_price_ck CHECK (unit_price_snapshot >= 0),
    CONSTRAINT consultation_lab_items_quantity_ck CHECK (quantity BETWEEN 1 AND 999),
    CONSTRAINT consultation_lab_items_consultation_product_uq UNIQUE (consultation_id, lab_product_id)
);

CREATE INDEX consultation_lab_items_consultation_idx
    ON public.consultation_lab_items (consultation_id, created_at, id);
CREATE INDEX consultation_lab_items_patient_idx
    ON public.consultation_lab_items (patient_id, created_at DESC, id DESC);
CREATE INDEX consultation_lab_items_doctor_idx
    ON public.consultation_lab_items (doctor_id, created_at DESC, id DESC);
CREATE INDEX consultation_lab_items_lab_idx
    ON public.consultation_lab_items (lab_id, created_at DESC, id DESC);
CREATE INDEX consultation_lab_items_product_idx
    ON public.consultation_lab_items (lab_product_id);

ALTER TABLE public.consultations ADD COLUMN lab_note text NULL;
ALTER TABLE public.consultations ADD CONSTRAINT consultations_lab_note_length_ck
    CHECK (lab_note IS NULL OR char_length(lab_note) <= 4000);

ALTER TABLE public.labs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.consultation_lab_items ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.labs FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.lab_products FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.consultation_lab_items FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION security.lab_actor()
RETURNS TABLE (id uuid, role text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
    SELECT app_user.id, app_user.role::text
      FROM public.users AS app_user
     WHERE app_user.supabase_user_id = auth.uid()
       AND app_user.is_active = true
       AND app_user.approved_at IS NOT NULL
       AND app_user.role IN ('doctor', 'admin')
     LIMIT 1
$function$;

CREATE OR REPLACE FUNCTION security.lab_money(p_value numeric)
RETURNS text
LANGUAGE sql IMMUTABLE
SET search_path = pg_catalog, pg_temp
AS $function$
    SELECT to_char(coalesce(p_value, 0), 'FM999999999999990.00')
$function$;

CREATE OR REPLACE FUNCTION public.list_labs(p_include_archived boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_result jsonb;
BEGIN
    SELECT actor.id INTO v_actor_id FROM security.lab_actor() AS actor;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'LAB_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
    SELECT coalesce(jsonb_agg(jsonb_build_object(
        'id', lab.id, 'name', lab.name, 'isActive', lab.is_active,
        'createdAt', lab.created_at, 'updatedAt', lab.updated_at
    ) ORDER BY lower(btrim(lab.name)), lab.id), '[]'::jsonb)
      INTO v_result FROM public.labs AS lab
     WHERE coalesce(p_include_archived, false) OR lab.is_active;
    RETURN v_result;
END
$function$;

CREATE OR REPLACE FUNCTION public.create_lab(p_name text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_lab public.labs%ROWTYPE;
BEGIN
    SELECT actor.id INTO v_actor_id FROM security.lab_actor() AS actor;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'LAB_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
    IF p_name IS NULL OR btrim(p_name)='' OR char_length(btrim(p_name))>200 THEN
        RAISE EXCEPTION 'LAB_NAME_INVALID' USING ERRCODE='22023';
    END IF;
    INSERT INTO public.labs(name, created_by) VALUES (btrim(p_name), v_actor_id)
    RETURNING * INTO v_lab;
    RETURN jsonb_build_object('id',v_lab.id,'name',v_lab.name,'isActive',v_lab.is_active);
EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'LAB_NAME_DUPLICATE' USING ERRCODE='23505';
END
$function$;

CREATE OR REPLACE FUNCTION public.archive_lab(p_lab_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_lab public.labs%ROWTYPE;
BEGIN
    SELECT actor.id INTO v_actor_id FROM security.lab_actor() AS actor;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'LAB_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
    UPDATE public.labs AS lab SET is_active=false, updated_at=now()
     WHERE lab.id=p_lab_id RETURNING * INTO v_lab;
    IF v_lab.id IS NULL THEN RAISE EXCEPTION 'LAB_NOT_FOUND' USING ERRCODE='P4001'; END IF;
    UPDATE public.lab_products SET is_active=false, updated_at=now()
     WHERE lab_id=p_lab_id AND is_active;
    RETURN jsonb_build_object('id',v_lab.id,'name',v_lab.name,'isActive',false);
END
$function$;

CREATE OR REPLACE FUNCTION public.list_lab_products(p_lab_id uuid, p_include_archived boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_result jsonb;
BEGIN
    SELECT actor.id INTO v_actor_id FROM security.lab_actor() AS actor;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'LAB_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.labs WHERE id=p_lab_id) THEN
        RAISE EXCEPTION 'LAB_NOT_FOUND' USING ERRCODE='P4001';
    END IF;
    SELECT coalesce(jsonb_agg(jsonb_build_object(
        'id', product.id, 'labId', product.lab_id, 'name', product.name,
        'currentPrice', security.lab_money(product.current_price),
        'isActive', product.is_active, 'createdAt', product.created_at,
        'updatedAt', product.updated_at
    ) ORDER BY lower(btrim(product.name)), product.id), '[]'::jsonb)
      INTO v_result FROM public.lab_products AS product
     WHERE product.lab_id=p_lab_id
       AND (coalesce(p_include_archived,false) OR product.is_active);
    RETURN v_result;
END
$function$;

CREATE OR REPLACE FUNCTION public.create_lab_product(p_lab_id uuid, p_name text, p_current_price numeric)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_product public.lab_products%ROWTYPE;
BEGIN
    SELECT actor.id INTO v_actor_id FROM security.lab_actor() AS actor;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'LAB_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.labs WHERE id=p_lab_id AND is_active) THEN
        RAISE EXCEPTION 'LAB_NOT_ACTIVE' USING ERRCODE='P4002';
    END IF;
    IF p_name IS NULL OR btrim(p_name)='' OR char_length(btrim(p_name))>200
       OR p_current_price IS NULL OR p_current_price<0 OR scale(p_current_price)>2 THEN
        RAISE EXCEPTION 'LAB_PRODUCT_INVALID' USING ERRCODE='22023';
    END IF;
    INSERT INTO public.lab_products(lab_id,name,current_price)
    VALUES (p_lab_id,btrim(p_name),p_current_price) RETURNING * INTO v_product;
    RETURN jsonb_build_object('id',v_product.id,'labId',v_product.lab_id,
        'name',v_product.name,'currentPrice',security.lab_money(v_product.current_price),'isActive',true);
EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'LAB_PRODUCT_NAME_DUPLICATE' USING ERRCODE='23505';
END
$function$;

CREATE OR REPLACE FUNCTION public.update_lab_product_price(p_lab_product_id uuid, p_current_price numeric)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_product public.lab_products%ROWTYPE;
BEGIN
    SELECT actor.id INTO v_actor_id FROM security.lab_actor() AS actor;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'LAB_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
    IF p_current_price IS NULL OR p_current_price<0 OR scale(p_current_price)>2 THEN
        RAISE EXCEPTION 'LAB_PRODUCT_PRICE_INVALID' USING ERRCODE='22023';
    END IF;
    UPDATE public.lab_products AS product
       SET current_price=p_current_price, updated_at=now()
     WHERE product.id=p_lab_product_id AND product.is_active
     RETURNING * INTO v_product;
    IF v_product.id IS NULL THEN RAISE EXCEPTION 'LAB_PRODUCT_NOT_ACTIVE' USING ERRCODE='P4003'; END IF;
    RETURN jsonb_build_object('id',v_product.id,'labId',v_product.lab_id,
        'name',v_product.name,'currentPrice',security.lab_money(v_product.current_price),'isActive',true);
END
$function$;

CREATE OR REPLACE FUNCTION public.archive_lab_product(p_lab_product_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_product public.lab_products%ROWTYPE;
BEGIN
    SELECT actor.id INTO v_actor_id FROM security.lab_actor() AS actor;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'LAB_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
    UPDATE public.lab_products AS product SET is_active=false, updated_at=now()
     WHERE product.id=p_lab_product_id RETURNING * INTO v_product;
    IF v_product.id IS NULL THEN RAISE EXCEPTION 'LAB_PRODUCT_NOT_FOUND' USING ERRCODE='P4004'; END IF;
    RETURN jsonb_build_object('id',v_product.id,'labId',v_product.lab_id,
        'name',v_product.name,'isActive',false);
END
$function$;

CREATE OR REPLACE FUNCTION public.get_consultation_lab_items(p_consultation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE v_actor_id uuid; v_actor_role text; v_consultation public.consultations%ROWTYPE; v_result jsonb;
BEGIN
    SELECT actor.id,actor.role INTO v_actor_id,v_actor_role FROM security.lab_actor() AS actor;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'LAB_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
    SELECT * INTO v_consultation FROM public.consultations WHERE id=p_consultation_id;
    IF v_consultation.id IS NULL THEN RAISE EXCEPTION 'LAB_CONSULTATION_NOT_FOUND' USING ERRCODE='P4005'; END IF;
    IF v_consultation.doctor_id IS NULL OR (v_actor_role='doctor' AND v_consultation.doctor_id<>v_actor_id) THEN
        RAISE EXCEPTION 'LAB_AUTHORIZATION_DENIED' USING ERRCODE='42501';
    END IF;
    SELECT jsonb_build_object(
        'consultationId',v_consultation.id,'patientId',v_consultation.patient_id,
        'labNote',v_consultation.lab_note,
        'items',coalesce(jsonb_agg(jsonb_build_object(
            'id',item.id,'labId',item.lab_id,'labProductId',item.lab_product_id,
            'labName',item.lab_name_snapshot,'productName',item.product_name_snapshot,
            'unitPrice',security.lab_money(item.unit_price_snapshot),
            'quantity',item.quantity,'totalAmount',security.lab_money(item.total_amount),
            'createdAt',item.created_at
        ) ORDER BY lower(item.lab_name_snapshot),lower(item.product_name_snapshot),item.id)
        FILTER (WHERE item.id IS NOT NULL),'[]'::jsonb))
      INTO v_result FROM public.consultation_lab_items AS item
     WHERE item.consultation_id=v_consultation.id;
    RETURN v_result;
END
$function$;

CREATE OR REPLACE FUNCTION public.save_consultation_lab_items(
    p_consultation_id uuid, p_items jsonb, p_lab_note text, p_lab_note_supplied boolean
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
DECLARE
    v_actor_id uuid; v_actor_role text; v_consultation public.consultations%ROWTYPE;
    v_item jsonb; v_product_id uuid; v_quantity integer; v_selected_ids uuid[]:=ARRAY[]::uuid[];
    v_product public.lab_products%ROWTYPE; v_lab public.labs%ROWTYPE;
BEGIN
    SELECT actor.id,actor.role INTO v_actor_id,v_actor_role FROM security.lab_actor() AS actor;
    IF v_actor_id IS NULL THEN RAISE EXCEPTION 'LAB_AUTHORIZATION_DENIED' USING ERRCODE='42501'; END IF;
    IF p_items IS NULL OR jsonb_typeof(p_items)<>'array' OR jsonb_array_length(p_items)>200
       OR p_lab_note_supplied IS NULL
       OR (p_lab_note_supplied AND p_lab_note IS NOT NULL AND char_length(p_lab_note)>4000) THEN
        RAISE EXCEPTION 'LAB_SELECTION_INVALID' USING ERRCODE='22023';
    END IF;
    SELECT consultation.* INTO v_consultation
      FROM public.consultations AS consultation
     WHERE consultation.id=p_consultation_id FOR UPDATE;
    IF v_consultation.id IS NULL THEN RAISE EXCEPTION 'LAB_CONSULTATION_NOT_FOUND' USING ERRCODE='P4005'; END IF;
    IF v_consultation.doctor_id IS NULL OR (v_actor_role='doctor' AND v_consultation.doctor_id<>v_actor_id) THEN
        RAISE EXCEPTION 'LAB_AUTHORIZATION_DENIED' USING ERRCODE='42501';
    END IF;
    IF v_consultation.appointment_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.appointments AS appointment
         WHERE appointment.id=v_consultation.appointment_id
           AND appointment.patient_id=v_consultation.patient_id
           AND appointment.doctor_id=v_consultation.doctor_id
           AND (appointment.date=CURRENT_DATE OR appointment.appointment_date=CURRENT_DATE)
           AND appointment.status::text IN ('pending','confirmed')
    ) THEN RAISE EXCEPTION 'LAB_CONSULTATION_NOT_ACTIVE' USING ERRCODE='P4006'; END IF;

    FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
        IF jsonb_typeof(v_item)<>'object'
           OR EXISTS (
               SELECT 1 FROM jsonb_object_keys(v_item) AS item_key(value)
                WHERE item_key.value NOT IN ('labProductId','quantity')
           )
           OR NOT (v_item ? 'labProductId') OR NOT (v_item ? 'quantity')
           OR NOT pg_input_is_valid(v_item->>'labProductId','uuid')
           OR NOT pg_input_is_valid(v_item->>'quantity','integer') THEN
            RAISE EXCEPTION 'LAB_SELECTION_ITEM_INVALID' USING ERRCODE='22023';
        END IF;
        v_product_id:=(v_item->>'labProductId')::uuid;
        v_quantity:=(v_item->>'quantity')::integer;
        IF v_quantity NOT BETWEEN 1 AND 999 OR v_product_id=ANY(v_selected_ids) THEN
            RAISE EXCEPTION 'LAB_SELECTION_ITEM_INVALID' USING ERRCODE='22023';
        END IF;
        SELECT product.* INTO v_product FROM public.lab_products AS product
         WHERE product.id=v_product_id AND product.is_active FOR SHARE;
        IF v_product.id IS NULL THEN RAISE EXCEPTION 'LAB_PRODUCT_NOT_ACTIVE' USING ERRCODE='P4003'; END IF;
        SELECT lab.* INTO v_lab FROM public.labs AS lab
         WHERE lab.id=v_product.lab_id AND lab.is_active FOR SHARE;
        IF v_lab.id IS NULL THEN RAISE EXCEPTION 'LAB_NOT_ACTIVE' USING ERRCODE='P4002'; END IF;
        INSERT INTO public.consultation_lab_items(
            consultation_id,patient_id,doctor_id,lab_id,lab_product_id,
            lab_name_snapshot,product_name_snapshot,unit_price_snapshot,quantity
        ) VALUES (
            v_consultation.id,v_consultation.patient_id,v_consultation.doctor_id,
            v_lab.id,v_product.id,v_lab.name,v_product.name,v_product.current_price,v_quantity
        ) ON CONFLICT (consultation_id,lab_product_id) DO UPDATE
             SET quantity=excluded.quantity;
        v_selected_ids:=array_append(v_selected_ids,v_product_id);
    END LOOP;
    DELETE FROM public.consultation_lab_items AS item
     WHERE item.consultation_id=v_consultation.id
       AND NOT (item.lab_product_id=ANY(v_selected_ids));
    IF p_lab_note_supplied THEN
        UPDATE public.consultations SET lab_note=nullif(btrim(p_lab_note),'')
         WHERE id=v_consultation.id;
    END IF;
    RETURN public.get_consultation_lab_items(v_consultation.id);
END
$function$;

REVOKE ALL ON FUNCTION security.lab_actor() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION security.lab_money(numeric) FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.list_labs(boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_lab(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.archive_lab(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_lab_products(uuid,boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_lab_product(uuid,text,numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_lab_product_price(uuid,numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.archive_lab_product(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_consultation_lab_items(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.save_consultation_lab_items(uuid,jsonb,text,boolean) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.list_labs(boolean) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_lab(text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.archive_lab(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.list_lab_products(uuid,boolean) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_lab_product(uuid,text,numeric) FROM anon;
REVOKE EXECUTE ON FUNCTION public.update_lab_product_price(uuid,numeric) FROM anon;
REVOKE EXECUTE ON FUNCTION public.archive_lab_product(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_consultation_lab_items(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.save_consultation_lab_items(uuid,jsonb,text,boolean) FROM anon;

GRANT EXECUTE ON FUNCTION public.list_labs(boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_lab(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.archive_lab(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_lab_products(uuid,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_lab_product(uuid,text,numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_lab_product_price(uuid,numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.archive_lab_product(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_consultation_lab_items(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_consultation_lab_items(uuid,jsonb,text,boolean) TO authenticated;

COMMIT;
