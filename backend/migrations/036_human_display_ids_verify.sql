-- Migration 036 verification. READ ONLY and rerunnable.
WITH targets(table_name,prefix) AS(
  VALUES('patients','P'),('appointments','A'),('consultations','C')
), expected_fks(source_table,source_column,target_table,target_column) AS(
  VALUES ('appointments','patient_id','patients','id'),('appointments','doctor_id','users','id'),
    ('consultations','patient_id','patients','id'),('consultations','doctor_id','users','id'),
    ('consultations','appointment_id','appointments','id')
), functions AS(
  SELECT p.oid,n.nspname schema_name,p.proname,p.prosecdef,p.proconfig,p.provolatile,
    lower(pg_get_functiondef(p.oid)) definition
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE p.oid IN(
    to_regprocedure('security.allocate_display_id(text,timestamp with time zone)'),
    to_regprocedure('security.assign_display_id()'),to_regprocedure('security.reject_display_id_change()'),
    to_regprocedure('security.appointment_projection(uuid)'),
    to_regprocedure('security.financial_billing_projection(uuid)'),
    to_regprocedure('public.get_appointments()'),to_regprocedure('public.get_or_initialize_consultation(uuid)'),
    to_regprocedure('public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean)'),
    to_regprocedure('public.get_patient_consultation_history(uuid)'),
    to_regprocedure('public.list_doctor_consultation_history()'),
    to_regprocedure('public.list_lab_transactions(uuid,timestamp with time zone,timestamp with time zone)'))
), bases AS(
  SELECT p.oid,n.nspname schema_name,p.proname,p.prosecdef,p.proconfig,p.provolatile,
    lower(pg_get_functiondef(p.oid)) definition
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE p.oid IN(
    to_regprocedure('security.appointment_projection_036_base(uuid)'),
    to_regprocedure('security.get_appointments_036_base()'),
    to_regprocedure('security.get_or_initialize_consultation_036_base(uuid)'),
    to_regprocedure('security.save_current_consultation_036_base(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean)'),
    to_regprocedure('security.get_patient_consultation_history_036_base(uuid)'),
    to_regprocedure('security.list_doctor_consultation_history_036_base()'),
    to_regprocedure('security.financial_billing_projection_036_base(uuid)'),
    to_regprocedure('security.list_lab_transactions_036_base(uuid,timestamp with time zone,timestamp with time zone)'))
), checks(ordinal,check_name,status,detail) AS(
  SELECT 5,'objects.required',CASE WHEN to_regclass('public.display_id_counters') IS NOT NULL
    AND (SELECT count(*) FROM functions)=11 AND (SELECT count(*) FROM bases)=8 THEN 'PASS' ELSE 'FAIL' END,
    'counter, all 11 helper/wrapper signatures, and all 8 exact base signatures exist'
  UNION ALL
  SELECT 10,'column.'||t.table_name,CASE WHEN c.data_type='text' AND c.is_nullable='NO' THEN 'PASS' ELSE 'FAIL' END,
    coalesce(c.data_type||' nullable='||c.is_nullable,'missing')
  FROM targets t LEFT JOIN information_schema.columns c ON c.table_schema='public'
    AND c.table_name=t.table_name AND c.column_name='display_id'
  UNION ALL
  SELECT 20,'identity_constraints.'||t.table_name,CASE WHEN
    EXISTS(SELECT 1 FROM pg_constraint c WHERE c.conrelid=to_regclass('public.'||t.table_name)
      AND c.contype='u' AND pg_get_constraintdef(c.oid)='UNIQUE (display_id)')
    AND EXISTS(SELECT 1 FROM pg_constraint c WHERE c.conrelid=to_regclass('public.'||t.table_name)
      AND c.contype='c' AND pg_get_constraintdef(c.oid) LIKE '%^'||t.prefix||'-%[0-9]{5}$%')
    THEN 'PASS' ELSE 'FAIL' END,'UNIQUE and exact-prefix/five-digit CHECK' FROM targets t
  UNION ALL
  SELECT 30,'uuid_primary_key.'||t.table_name,CASE WHEN EXISTS(
    SELECT 1 FROM pg_constraint c JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=ANY(c.conkey)
    WHERE c.conrelid=to_regclass('public.'||t.table_name) AND c.contype='p'
      AND cardinality(c.conkey)=1 AND a.attname='id' AND a.atttypid='uuid'::regtype)
    THEN 'PASS' ELSE 'FAIL' END,'id remains sole UUID primary key' FROM targets t
  UNION ALL
  SELECT 40,'uuid_foreign_key.'||fk.source_table||'.'||fk.source_column,CASE WHEN
    sa.atttypid='uuid'::regtype AND ta.atttypid='uuid'::regtype AND EXISTS(
      SELECT 1 FROM pg_constraint c WHERE c.contype='f' AND c.conrelid=sc.oid AND c.confrelid=tc.oid
        AND c.conkey=ARRAY[sa.attnum]::smallint[] AND c.confkey=ARRAY[ta.attnum]::smallint[])
    THEN 'PASS' ELSE 'FAIL' END,
    fk.source_table||'.'||fk.source_column||' -> '||fk.target_table||'.'||fk.target_column||
      ' types='||coalesce(format_type(sa.atttypid,NULL),'missing')||'/'||coalesce(format_type(ta.atttypid,NULL),'missing')
  FROM expected_fks fk
  LEFT JOIN pg_class sc ON sc.oid=to_regclass('public.'||fk.source_table)
  LEFT JOIN pg_attribute sa ON sa.attrelid=sc.oid AND sa.attname=fk.source_column AND NOT sa.attisdropped
  LEFT JOIN pg_class tc ON tc.oid=to_regclass('public.'||fk.target_table)
  LEFT JOIN pg_attribute ta ON ta.attrelid=tc.oid AND ta.attname=fk.target_column AND NOT ta.attisdropped
  UNION ALL
  SELECT 50,'counter.columns',CASE WHEN
    (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='display_id_counters')=3
    AND (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='display_id_counters'
      AND ((column_name='entity_type' AND data_type='text') OR (column_name='year_month' AND data_type='text')
        OR (column_name='current_value' AND data_type='integer')) AND is_nullable='NO')=3
    THEN 'PASS' ELSE 'FAIL' END,'exact three required NOT NULL columns and types'
  UNION ALL
  SELECT 60,'counter.constraints',CASE WHEN
    EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid=to_regclass('public.display_id_counters')
      AND contype='p' AND pg_get_constraintdef(oid)='PRIMARY KEY (entity_type, year_month)')
    AND (SELECT count(*) FROM pg_constraint WHERE conrelid=to_regclass('public.display_id_counters')
      AND contype='c' AND ((pg_get_constraintdef(oid) LIKE '%entity_type%patients%appointments%consultations%')
        OR (pg_get_constraintdef(oid) LIKE '%year_month%[0-9]{6}%')
        OR (pg_get_constraintdef(oid) LIKE '%current_value%1%99999%')))=3
    THEN 'PASS' ELSE 'FAIL' END,'composite PK; entity, YYYYMM, and 1..99999 CHECKs'
  UNION ALL
  SELECT 70,'counter.protection',CASE WHEN c.relrowsecurity
    AND NOT has_table_privilege('anon','public.display_id_counters','INSERT,UPDATE,DELETE')
    AND NOT has_table_privilege('authenticated','public.display_id_counters','INSERT,UPDATE,DELETE')
    THEN 'PASS' ELSE 'FAIL' END,'RLS on; anon/authenticated cannot mutate'
  FROM pg_class c WHERE c.oid=to_regclass('public.display_id_counters')
  UNION ALL
  SELECT 71,'target_rls.'||t.table_name,CASE WHEN c.relrowsecurity THEN 'PASS' ELSE 'FAIL' END,
    'pre-existing target-table RLS remains enabled' FROM targets t
    LEFT JOIN pg_class c ON c.oid=to_regclass('public.'||t.table_name)
  UNION ALL
  SELECT 72,'patients.required_policies',CASE WHEN count(*) FILTER(WHERE policyname IN(
    'patient_select_policy','patient_insert_policy','patient_update_policy'))=3 THEN 'PASS' ELSE 'FAIL' END,
    coalesce(string_agg(policyname,', ' ORDER BY policyname),'none') FROM pg_policies
    WHERE schemaname='public' AND tablename='patients'
  UNION ALL
  SELECT 73,'internal_execute_denied.helpers',CASE WHEN count(*)=3 AND bool_and(
    NOT has_function_privilege('anon',oid,'EXECUTE')
    AND NOT has_function_privilege('authenticated',oid,'EXECUTE')
    AND NOT has_function_privilege('PUBLIC',oid,'EXECUTE')) THEN 'PASS' ELSE 'FAIL' END,
    'allocate, assign, and rejection helpers deny anon/authenticated/PUBLIC' FROM functions
    WHERE schema_name='security' AND proname IN('allocate_display_id','assign_display_id','reject_display_id_change')
  UNION ALL
  SELECT 74,'internal_execute_denied.bases',CASE WHEN count(*)=8 AND bool_and(
    NOT has_function_privilege('anon',oid,'EXECUTE')
    AND NOT has_function_privilege('authenticated',oid,'EXECUTE')
    AND NOT has_function_privilege('PUBLIC',oid,'EXECUTE')) THEN 'PASS' ELSE 'FAIL' END,
    'all eight *_036_base functions deny anon/authenticated/PUBLIC' FROM bases
  UNION ALL
  SELECT 75,'base.security_contract',CASE WHEN count(*)=8 AND bool_and(prosecdef
    AND proconfig @> ARRAY['search_path=pg_catalog, pg_temp']
    AND provolatile=CASE WHEN proname='save_current_consultation_036_base' THEN 'v'::"char" ELSE 's'::"char" END)
    THEN 'PASS' ELSE 'FAIL' END,'all bases preserve SECURITY DEFINER, search_path, and volatility' FROM bases
  UNION ALL
  SELECT 76,'internal_execute_denied.security_wrappers',CASE WHEN count(*)=2 AND bool_and(
    NOT has_function_privilege('anon',oid,'EXECUTE')
    AND NOT has_function_privilege('authenticated',oid,'EXECUTE')
    AND NOT has_function_privilege('PUBLIC',oid,'EXECUTE')) THEN 'PASS' ELSE 'FAIL' END,
    'appointment and financial security wrappers are internal-only' FROM functions
    WHERE schema_name='security' AND proname IN('appointment_projection','financial_billing_projection')
  UNION ALL
  SELECT 80,'allocator.atomic',CASE WHEN definition LIKE '%insert into public.display_id_counters%'
    AND definition LIKE '%on conflict%' AND definition LIKE '%do update%' AND definition LIKE '%returning%'
    AND definition LIKE '%africa/cairo%' AND definition LIKE '%99999%' AND definition NOT LIKE '%max(%'
    THEN 'PASS' ELSE 'FAIL' END,'atomic UPSERT RETURNING, Cairo, bounded, no MAX()'
  FROM functions WHERE schema_name='security' AND proname='allocate_display_id'
  UNION ALL
  SELECT 90,'insert_trigger.'||t.table_name,CASE WHEN EXISTS(SELECT 1 FROM pg_trigger g
    WHERE g.tgrelid=to_regclass('public.'||t.table_name) AND NOT g.tgisinternal AND g.tgtype=7
      AND g.tgfoid='security.assign_display_id()'::regprocedure) THEN 'PASS' ELSE 'FAIL' END,
    'row BEFORE INSERT -> security.assign_display_id()' FROM targets t
  UNION ALL
  SELECT 100,'server_timestamp.'||t.table_name,CASE WHEN EXISTS(SELECT 1 FROM pg_trigger g JOIN functions f ON f.oid=g.tgfoid
    WHERE g.tgrelid=to_regclass('public.'||t.table_name) AND g.tgtype=7
      AND f.definition LIKE '%clock_timestamp()%' AND f.definition LIKE '%new.created_at%'
      AND f.definition LIKE '%allocate_display_id%') THEN 'PASS' ELSE 'FAIL' END,
    'server clock_timestamp is stored and allocated' FROM targets t
  UNION ALL
  SELECT 110,'immutable.'||t.table_name,CASE WHEN EXISTS(SELECT 1 FROM pg_trigger g
    WHERE g.tgrelid=to_regclass('public.'||t.table_name) AND NOT g.tgisinternal AND g.tgtype=19
      AND g.tgfoid='security.reject_display_id_change()'::regprocedure
      AND (SELECT array_agg(a.attname::text ORDER BY a.attname) FROM unnest(g.tgattr::smallint[]) x(attnum)
        JOIN pg_attribute a ON a.attrelid=g.tgrelid AND a.attnum=x.attnum)=ARRAY['created_at','display_id'])
    THEN 'PASS' ELSE 'FAIL' END,'row BEFORE UPDATE OF created_at,display_id -> rejection function' FROM targets t
  UNION ALL
  SELECT 120,'data.sequence.'||t.table_name,CASE WHEN ((xpath('/row/count/text()',query_to_xml(format(
    'SELECT count(*) count FROM (SELECT to_char(created_at AT TIME ZONE %L,%L) ym,count(*) n,count(DISTINCT substring(display_id from 8 for 5)::integer) d,min(substring(display_id from 8 for 5)::integer) lo,max(substring(display_id from 8 for 5)::integer) hi FROM public.%I GROUP BY 1) m WHERE lo<>1 OR hi<>n OR d<>n OR hi>99999',
    'Africa/Cairo','YYYYMM',t.table_name),false,true,'')))[1]::text)::bigint=0 THEN 'PASS' ELSE 'FAIL' END,
    'every entity/month contiguous 1..row_count, no duplicates, <=99999' FROM targets t
  UNION ALL
  SELECT 130,'data.created_month.'||t.table_name,CASE WHEN ((xpath('/row/count/text()',query_to_xml(format(
    'SELECT count(*) count FROM public.%I WHERE display_id IS NULL OR substring(display_id from 3 for 4)<>to_char(created_at AT TIME ZONE %L,%L)',
    t.table_name,'Africa/Cairo','MMYY'),false,true,'')))[1]::text)::bigint=0 THEN 'PASS' ELSE 'FAIL' END,
    'all rows assigned; immutable created_at matches Cairo MMYY' FROM targets t
  UNION ALL
  SELECT 140,'counter.covers_sequences',CASE WHEN NOT EXISTS(SELECT 1 FROM(
    SELECT 'patients'::text entity_type,to_char(created_at AT TIME ZONE 'Africa/Cairo','YYYYMM') year_month,
      max(substring(display_id from 8 for 5)::integer) highest FROM public.patients GROUP BY 1,2
    UNION ALL SELECT 'appointments',to_char(created_at AT TIME ZONE 'Africa/Cairo','YYYYMM'),
      max(substring(display_id from 8 for 5)::integer) FROM public.appointments GROUP BY 1,2
    UNION ALL SELECT 'consultations',to_char(created_at AT TIME ZONE 'Africa/Cairo','YYYYMM'),
      max(substring(display_id from 8 for 5)::integer) FROM public.consultations GROUP BY 1,2
  ) a LEFT JOIN public.display_id_counters c USING(entity_type,year_month)
    WHERE c.current_value IS NULL OR c.current_value<a.highest OR a.highest>99999)
    THEN 'PASS' ELSE 'FAIL' END,'counter >= highest assigned serial for every entity/month'
  UNION ALL
  SELECT 150,'rpc.security.'||schema_name||'.'||proname,CASE WHEN prosecdef
    AND proconfig @> ARRAY['search_path=pg_catalog, pg_temp']
    AND provolatile=CASE WHEN proname IN('allocate_display_id','assign_display_id','save_current_consultation')
      THEN 'v'::"char" ELSE 's'::"char" END THEN 'PASS' ELSE 'FAIL' END,
    'SECURITY DEFINER, restricted search_path, and preserved volatility' FROM functions
    WHERE schema_name='public' OR proname IN('allocate_display_id','assign_display_id','appointment_projection','financial_billing_projection')
  UNION ALL
  SELECT 151,'rpc.public_grants',CASE WHEN count(*)=6 AND bool_and(
    has_function_privilege('authenticated',oid,'EXECUTE')
    AND NOT has_function_privilege('anon',oid,'EXECUTE')
    AND NOT has_function_privilege('PUBLIC',oid,'EXECUTE')) THEN 'PASS' ELSE 'FAIL' END,
    'six public RPCs: authenticated execute; anon/PUBLIC denied' FROM functions
    WHERE schema_name='public'
  UNION ALL
  SELECT 160,'projection.appointment',CASE WHEN
    (SELECT definition LIKE '%appointment_projection_036_base%'
      AND definition LIKE '%appointment.display_id%' FROM functions
      WHERE schema_name='security' AND proname='appointment_projection')
    AND (SELECT definition LIKE '%get_appointments_036_base()%'
      AND definition LIKE '%with ordinality%' AND definition LIKE '%order by base.ordinality%'
      AND definition LIKE '%appointment.display_id%'
      AND replace(pg_get_function_result(oid),'"','')=
        'TABLE(id uuid, display_id text, patient_id uuid, patient text, doctor_id uuid, doctor text, date date, time text, type text, status text, condition text, notes text)'
      FROM functions WHERE schema_name='public' AND proname='get_appointments')
    AND (SELECT count(*) FROM bases WHERE proname IN('appointment_projection_036_base','get_appointments_036_base'))=2
    THEN 'PASS' ELSE 'FAIL' END,
    'both wrappers call preserved bases, read appointments.display_id, retain UUID id, and preserve base order'
  UNION ALL
  SELECT 161,'projection.current_consultation',CASE WHEN count(*)=2
    AND bool_and(definition LIKE '%displayid%' AND definition LIKE '%display_id%') THEN 'PASS' ELSE 'FAIL' END,
    'get/initialize and save emit stored consultation displayId' FROM functions
    WHERE schema_name='public' AND proname IN('get_or_initialize_consultation','save_current_consultation')
  UNION ALL
  SELECT 162,'projection.history',CASE WHEN count(*)=2 AND bool_and(definition LIKE '%patientdisplayid%'
    AND definition LIKE '%patient.display_id%' AND definition LIKE '%consultationdisplayid%'
    AND definition LIKE '%consultation.display_id%') THEN 'PASS' ELSE 'FAIL' END,
    'both history RPCs emit stored patient and consultation IDs' FROM functions
    WHERE schema_name='public' AND proname IN('get_patient_consultation_history','list_doctor_consultation_history')
  UNION ALL
  SELECT 163,'projection.finance',CASE WHEN definition LIKE '%consultationdisplayid%'
    AND definition LIKE '%consultation.display_id%' AND definition LIKE '%patient.display_id%'
    AND definition LIKE '%displayid%' THEN 'PASS' ELSE 'FAIL' END,
    'finance emits stored consultation and patient IDs' FROM functions
    WHERE schema_name='security' AND proname='financial_billing_projection'
  UNION ALL
  SELECT 164,'projection.lab',CASE WHEN definition LIKE '%consultationdisplayid%'
    AND definition LIKE '%consultation.display_id%' THEN 'PASS' ELSE 'FAIL' END,
    'lab transactions emit stored consultation ID' FROM functions
    WHERE schema_name='public' AND proname='list_lab_transactions'
  UNION ALL
  SELECT 170,'base_binding.save',CASE WHEN
    to_regprocedure('security.save_current_consultation_036_base(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean)') IS NOT NULL
    AND NOT EXISTS(SELECT 1 FROM pg_depend d JOIN pg_proc p ON p.oid=d.objid
    WHERE d.classid='pg_proc'::regclass AND d.deptype='n'
      AND d.refobjid=to_regprocedure('security.save_current_consultation_036_base(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean)')
      AND p.oid<>to_regprocedure('public.save_current_consultation(uuid,jsonb,integer,integer,text,boolean,jsonb,boolean,jsonb,boolean)'))
    THEN 'PASS' ELSE 'FAIL' END,'only wrapper remains bound to save base'
  UNION ALL
  SELECT 171,'base_binding.finance',CASE WHEN
    to_regprocedure('security.financial_billing_projection_036_base(uuid)') IS NOT NULL
    AND NOT EXISTS(SELECT 1 FROM pg_depend d JOIN pg_proc p ON p.oid=d.objid
    WHERE d.classid='pg_proc'::regclass AND d.deptype='n'
      AND d.refobjid=to_regprocedure('security.financial_billing_projection_036_base(uuid)')
      AND p.oid<>to_regprocedure('security.financial_billing_projection(uuid)'))
    THEN 'PASS' ELSE 'FAIL' END,'only wrapper remains bound to finance base'
  UNION ALL
  SELECT 172,'base_binding.json_wrappers',CASE WHEN (SELECT count(*) FROM bases)=8 AND NOT EXISTS(
    SELECT 1 FROM (VALUES
      (to_regprocedure('security.appointment_projection_036_base(uuid)'),to_regprocedure('security.appointment_projection(uuid)')),
      (to_regprocedure('security.get_appointments_036_base()'),to_regprocedure('public.get_appointments()')),
      (to_regprocedure('security.get_or_initialize_consultation_036_base(uuid)'),to_regprocedure('public.get_or_initialize_consultation(uuid)')),
      (to_regprocedure('security.get_patient_consultation_history_036_base(uuid)'),to_regprocedure('public.get_patient_consultation_history(uuid)')),
      (to_regprocedure('security.list_doctor_consultation_history_036_base()'),to_regprocedure('public.list_doctor_consultation_history()')),
      (to_regprocedure('security.list_lab_transactions_036_base(uuid,timestamp with time zone,timestamp with time zone)'),
       to_regprocedure('public.list_lab_transactions(uuid,timestamp with time zone,timestamp with time zone)'))
    ) pair(base_oid,wrapper_oid) JOIN pg_depend d ON d.refobjid=pair.base_oid
      JOIN pg_proc p ON p.oid=d.objid
    WHERE d.classid='pg_proc'::regclass AND d.deptype='n' AND p.oid<>pair.wrapper_oid)
    THEN 'PASS' ELSE 'FAIL' END,'renamed JSON bases have no bypassing stored-function dependencies'
  UNION ALL
  SELECT 180,'out_of_scope_tables',CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END,
    'unexpected display_id columns='||count(*) FROM information_schema.columns
    WHERE table_schema='public' AND column_name='display_id'
      AND table_name NOT IN('patients','appointments','consultations')
), output AS(
  SELECT ordinal,check_name,status,detail FROM checks
  UNION ALL SELECT 9999,'migration_036.overall',CASE WHEN count(*) FILTER(WHERE status='FAIL')=0 THEN 'PASS' ELSE 'FAIL' END,
    format('checks=%s pass=%s fail=%s',count(*),count(*) FILTER(WHERE status='PASS'),count(*) FILTER(WHERE status='FAIL')) FROM checks
)
SELECT check_name,status,detail FROM output ORDER BY ordinal,check_name;
