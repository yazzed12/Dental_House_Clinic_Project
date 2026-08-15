import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / 'migrations' / '025_settings_supabase_foundation.sql'
PREFLIGHT = ROOT / 'migrations' / '025_settings_supabase_foundation_preflight.sql'
VERIFY = ROOT / 'migrations' / '025_settings_supabase_foundation_verify.sql'


class SettingsSupabaseSqlContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text()
        cls.normalized = re.sub(r'\s+', ' ', cls.sql.lower())
        cls.preflight = PREFLIGHT.read_text().lower()
        cls.verify = VERIFY.read_text().lower()

    def body(self, name):
        matches = re.findall(rf'create function public\.{name}\([\s\S]*?\$function\$;', self.sql, re.I)
        self.assertTrue(matches, f'missing {name}')
        return re.sub(r'\s+', ' ', matches[-1].lower())

    def test_preflight_is_read_only_consolidated_and_complete(self):
        executable = re.sub(r'--[^\n]*', '', self.preflight)
        self.assertNotRegex(executable, r'(?m)^\s*(insert|update|delete|alter|drop|create|grant|revoke|truncate)\b')
        self.assertIn('select check_name,status,details', self.preflight)
        for marker in ('clinic_settings.columns','clinic_settings.row_model','clinic_settings.security',
                       'users.identity_mapping','existing.get_current_app_profile',
                       'existing.finalize_clinical_report','clean: migration 025 settings assumptions match current schema'):
            self.assertIn(marker, self.preflight)

    def test_existing_tables_are_not_recreated_or_data_rewritten(self):
        self.assertNotIn('create table public.clinic_settings', self.normalized)
        self.assertNotIn('create table public.users', self.normalized)
        self.assertNotIn('delete from public.clinic_settings', self.normalized)
        self.assertNotIn('insert into public.clinic_settings', self.normalized)
        self.assertNotIn('update public.users set', self.normalized)

    def test_actor_is_supabase_derived_active_approved_staff(self):
        self.assertIn('app_user.supabase_user_id=auth.uid()', self.normalized.replace(' ', ''))
        self.assertIn('app_user.is_active=true', self.normalized.replace(' ', ''))
        self.assertIn('app_user.approved_at is not null', self.normalized)
        self.assertIn("app_user.rolein('doctor','admin','receptionist')", self.normalized.replace(' ', ''))
        self.assertNotIn("'patient'", self.normalized)

    def test_clinic_update_only_touches_four_visible_fields(self):
        body = self.body('update_clinic_settings')
        for field in ('name=btrim(p_name)', 'email=nullif(btrim(p_email)', 'phone=nullif(btrim(p_phone)', 'address=nullif(btrim(p_address)'):
            self.assertIn(field, body.replace(' ', ''))
        for hidden in ('working_hours','appointment_duration','services','notification_settings'):
            self.assertNotIn(hidden, body)
        self.assertIn("v_actor_role not in ('doctor','admin')", body)

    def test_profile_update_is_self_only_and_cannot_spoof_role(self):
        body = self.body('update_current_app_profile')
        self.assertIn('app_user.id=v_actor_id', body.replace(' ', ''))
        self.assertIn('app_user.supabase_user_id=auth.uid()', body.replace(' ', ''))
        self.assertIn("v_actor_role<>'doctor'", body.replace(' ', ''))
        self.assertNotIn('p_user_id', body); self.assertNotIn('p_role', body)
        set_clause = body.split(' update public.users as app_user set ', 1)[1].split(' where ', 1)[0]
        for protected in ('role', 'is_active', 'approved_at', 'supabase_user_id'):
            self.assertNotRegex(set_clause, rf'(?:^|,)\s*{protected}\s*=')

    def test_rpc_security_and_report_compatibility(self):
        for signature in ('get_clinic_settings()', 'update_clinic_settings(text,text,text,text)', 'update_current_app_profile(text,text,text)'):
            self.assertIn(f'revoke all on function public.{signature} from public', self.normalized)
            self.assertIn(f'grant execute on function public.{signature} to authenticated', self.normalized)
        self.assertIn('acl.grantee=0', self.verify)
        self.assertIn('public.finalize_clinical_report(uuid,jsonb,text,text)', self.verify)
        self.assertIn('verification successful: simplified supabase settings foundation is contained and report-compatible', self.verify)
        self.assertNotIn('create or replace function public.finalize_clinical_report', self.normalized)


if __name__ == '__main__': unittest.main()
