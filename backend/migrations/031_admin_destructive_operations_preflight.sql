-- Migration 031 preflight. Read-only; run manually before the migration.
DO $preflight$
DECLARE v_missing text;
BEGIN
  SELECT string_agg(name,', ' ORDER BY name) INTO v_missing
  FROM unnest(ARRAY['notifications','financial_payment_allocations','financial_charge_adjustments',
    'financial_payment_records','consultation_procedures','lab_payments','consultation_lab_items',
    'clinical_reports','patient_dental_state','records','logs','consultations','appointments','patients']) name
  WHERE to_regclass('public.'||name) IS NULL;
  IF v_missing IS NOT NULL THEN RAISE EXCEPTION 'CONFLICT: missing approved format tables: %',v_missing; END IF;
  IF to_regclass('public.users') IS NULL OR to_regclass('public.clinic_settings') IS NULL
     OR to_regclass('public.labs') IS NULL OR to_regclass('public.lab_products') IS NULL
     OR to_regprocedure('security.admin_user_actor()') IS NULL THEN
    RAISE EXCEPTION 'CONFLICT: preserved/admin identity foundation is incomplete';
  END IF;
END
$preflight$;

WITH approved(name) AS (VALUES
 ('notifications'),('financial_payment_allocations'),('financial_charge_adjustments'),
 ('financial_payment_records'),('consultation_procedures'),('lab_payments'),
 ('consultation_lab_items'),('clinical_reports'),('patient_dental_state'),('records'),
 ('logs'),('consultations'),('appointments'),('patients')
), checks AS (
 SELECT 10 ordinal,'format.row_counts' check_name,'INFO' status,
   jsonb_object_agg(approved.name,(xpath('/row/count/text()',query_to_xml(
     format('select count(*) as count from public.%I',approved.name),false,true,'')))[1]::text::bigint)::text details
 FROM approved
 UNION ALL SELECT 20,'format.additional_fk_children',CASE WHEN count(*)=0 THEN 'OK' ELSE 'CONFLICT' END,
   coalesce(jsonb_agg(format('%I.%I -> %s',child.relname,attribute.attname,parent.relname) ORDER BY child.relname),'[]'::jsonb)::text
 FROM pg_constraint constraint_row
 JOIN pg_class child ON child.oid=constraint_row.conrelid
 JOIN pg_namespace child_ns ON child_ns.oid=child.relnamespace AND child_ns.nspname='public'
 JOIN pg_class parent ON parent.oid=constraint_row.confrelid
 JOIN LATERAL unnest(constraint_row.conkey) key(attnum) ON true
 JOIN pg_attribute attribute ON attribute.attrelid=child.oid AND attribute.attnum=key.attnum
 WHERE constraint_row.contype='f' AND parent.relname IN(SELECT name FROM approved)
   AND child.relname NOT IN(SELECT name FROM approved)
 UNION ALL SELECT 30,'format.lab_payment_trigger','INFO',coalesce(jsonb_agg(pg_get_triggerdef(t.oid)),'[]'::jsonb)::text
 FROM pg_trigger t WHERE t.tgrelid='public.lab_payments'::regclass AND NOT t.tgisinternal
 UNION ALL SELECT 40,'preserved.counts','INFO',jsonb_build_object(
   'users',(SELECT count(*) FROM public.users),'authLinkedUsers',(SELECT count(*) FROM public.users WHERE supabase_user_id IS NOT NULL),
   'clinicSettings',(SELECT count(*) FROM public.clinic_settings),'labs',(SELECT count(*) FROM public.labs),
   'labProducts',(SELECT count(*) FROM public.lab_products),'procedures',(SELECT count(*) FROM public.clinic_procedures),
   'symptoms',(SELECT count(*) FROM public.symptoms),'appointmentConditions',(SELECT count(*) FROM public.appointment_conditions))::text
 UNION ALL SELECT 50,'account.users_columns','INFO',coalesce(jsonb_agg(to_jsonb(c) ORDER BY c.column_name),'[]'::jsonb)::text
 FROM information_schema.columns c WHERE c.table_schema='public' AND c.table_name='users'
 UNION ALL SELECT 60,'account.user_references','INFO',coalesce(jsonb_agg(jsonb_build_object(
   'table',child.relname,'constraint',constraint_row.conname,'definition',pg_get_constraintdef(constraint_row.oid)) ORDER BY child.relname,constraint_row.conname),'[]'::jsonb)::text
 FROM pg_constraint constraint_row JOIN pg_class child ON child.oid=constraint_row.conrelid
 WHERE constraint_row.contype='f' AND constraint_row.confrelid='public.users'::regclass
 UNION ALL SELECT 70,'account.admin_count','INFO',jsonb_build_object('activeApproved',count(*))::text
 FROM public.users WHERE role::text='admin' AND is_active=true AND approved_at IS NOT NULL
 UNION ALL SELECT 80,'account.unlinked_users','INFO',jsonb_build_object('count',count(*))::text
 FROM public.users WHERE supabase_user_id IS NULL
 UNION ALL SELECT 90,'identity.admin_actor','INFO',pg_get_functiondef('security.admin_user_actor()'::regprocedure)
 UNION ALL SELECT 100,'identity.active_selectors','INFO',coalesce(jsonb_agg(p.oid::regprocedure::text ORDER BY p.oid::regprocedure::text),'[]'::jsonb)::text
 FROM pg_proc p WHERE p.prokind='f' AND lower(pg_get_functiondef(p.oid)) LIKE '%is_active%true%approved_at%is not null%'
 UNION ALL SELECT 105,'security.service_role',CASE WHEN EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN 'OK' ELSE 'CONFLICT' END,
   'service_role must exist for Edge Function-only preparation/finalization ACLs'
 UNION ALL SELECT 110,'notification.recipient_fk','INFO',coalesce(jsonb_agg(pg_get_constraintdef(c.oid)),'[]'::jsonb)::text
 FROM pg_constraint c WHERE c.contype='f' AND c.conrelid='public.notifications'::regclass
 UNION ALL SELECT 120,'target.conflicts',CASE WHEN count(*)=0 THEN 'OK' ELSE 'CONFLICT' END,
   coalesce(jsonb_agg(conflict),'[]'::jsonb)::text FROM (
    SELECT 'users deletion columns already exist' conflict WHERE EXISTS(SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='users' AND column_name IN('deleted_at','deletion_status'))
    UNION ALL SELECT 'format_clinic_data() exists' WHERE to_regprocedure('public.format_clinic_data()') IS NOT NULL
    UNION ALL SELECT 'prepare function exists' WHERE to_regprocedure('public.prepare_admin_account_deletion(uuid,uuid)') IS NOT NULL
    UNION ALL SELECT 'finalize function exists' WHERE to_regprocedure('public.finalize_admin_account_deletion(uuid)') IS NOT NULL
   ) conflicts
), summary AS (
 SELECT 999 ordinal,'summary' check_name,CASE WHEN bool_or(status='CONFLICT') THEN 'CONFLICT' ELSE 'CLEAN' END status,
 CASE WHEN bool_or(status='CONFLICT') THEN 'CONFLICT: Migration 031 Admin destructive-operation assumptions do not match current schema'
 ELSE 'CLEAN: Migration 031 Admin destructive-operation assumptions match current schema' END details FROM checks
)
SELECT check_name,status,details FROM (SELECT * FROM checks UNION ALL SELECT * FROM summary) report ORDER BY ordinal;
