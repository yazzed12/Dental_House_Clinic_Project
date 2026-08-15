import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LINK = ROOT / 'backend' / 'manual' / 'ADMIN-0A_link_existing_admin_supabase_auth.sql'
EDGE = ROOT / 'supabase' / 'functions' / 'login' / 'index.ts'
AUTH_CONTEXT = ROOT / 'src' / 'context' / 'AuthContext.jsx'


class AdminAuthLinkContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.link = LINK.read_text().lower()
        cls.edge = EDGE.read_text()
        cls.context = AUTH_CONTEXT.read_text()

    def test_link_reuses_exact_existing_admin_and_never_inserts(self):
        executable = re.sub(r'--[^\n]*', '', self.link)
        self.assertNotRegex(executable, r'\binsert\s+into\s+public\.users\b')
        self.assertIn("lower(app_user.email::text) = 'admin@admin.com'", self.link)
        self.assertIn("btrim(app_user.full_name::text) = 'yazzed elameir'", self.link)
        self.assertIn("app_user.role::text = 'admin'", self.link)
        self.assertIn('app_user.id = v_expected_app_user_id', self.link)

    def test_link_changes_only_supabase_identity_and_fails_closed(self):
        update = re.search(r'update public\.users[\s\S]*?get diagnostics', self.link).group(0)
        self.assertIn('set supabase_user_id = v_auth_user_id', update)
        for protected in ('email =', 'full_name =', 'role =', 'is_active =', 'approved_at =', 'personal_email ='):
            self.assertNotIn(protected, update)
        for guard in ('admin_link_uuid_placeholders_not_replaced',
                      'admin_link_expected_application_row_not_found',
                      'admin_link_application_row_already_linked',
                      'admin_link_private_auth_email_missing',
                      'admin_link_auth_user_not_found',
                      'admin_link_auth_email_does_not_match_private_email',
                      'admin_link_auth_id_already_used'):
            self.assertIn(guard, self.link)

    def test_clinic_email_and_private_auth_email_remain_distinct(self):
        self.assertIn("'admin@admin.com'", self.link)
        self.assertIn('auth_user.email', self.link)
        self.assertIn('v_admin.personal_email', self.link)
        self.assertNotIn('set email =', self.link)

    def test_edge_enforces_link_eligibility_identity_and_workspace(self):
        for marker in ('role, is_active, approved_at, supabase_user_id',
                       '!userProfile.is_active', '!userProfile.approved_at',
                       '!userProfile.supabase_user_id', 'AUTH_BRIDGE_IDENTITY_MISMATCH',
                       "String(userProfile.role).toLowerCase() !== normalizedWorkspace"):
            self.assertIn(marker, self.edge)
        self.assertIn("body: { clinic_email: clinicEmail, password, workspace }", (ROOT / 'src/services/authService.js').read_text())
        self.assertIn('authService.signIn(username, password, role)', self.context)

    def test_no_add_user_or_browser_admin_api_is_introduced(self):
        changed_sources = self.edge + self.context + (ROOT / 'src/services/authService.js').read_text()
        self.assertNotIn('auth.admin.', changed_sources)
        self.assertNotIn('createUser(', changed_sources)
        self.assertNotIn('SUPABASE_SERVICE_ROLE_KEY', (ROOT / 'src/services/authService.js').read_text())


if __name__ == '__main__':
    unittest.main()
