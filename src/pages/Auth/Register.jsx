import React, { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';
import AuthShell from '../../components/AuthShell';
import { ArrowLeft, ArrowRight, Building2, Lock, Mail, Stethoscope, User, UserPlus, Phone, Tag, AlertCircle, CheckCircle2, Eye, EyeOff } from 'lucide-react';

export default function Register() {
  const [formData, setFormData] = useState({
    username: '',
    name: '',
    phone: '',
    specialization: '',
    role: 'doctor',
    personal_email: '',
    password: '',
    confirmPassword: ''
  });
  
  const [personalEmailError, setPersonalEmailError] = useState('');
  const [errorMsg, setErrorMsg] = useState('');
  const [loadingState, setLoadingState] = useState(false);
  const [showVerification, setShowVerification] = useState(false);
  const [verificationCode, setVerificationCode] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);
  
  const { register, verify } = useAuth();
  const navigate = useNavigate();

  // Validate personal email format
  const validatePersonalEmail = (email) => {
    if (!email) return 'Personal email is required';
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) return 'Invalid email format';
    return '';
  };

  const updateField = (field, value) => {
    setErrorMsg('');
    setFormData((current) => {
      const updated = { ...current, [field]: value };
      if (field === 'personal_email') {
        setPersonalEmailError(validatePersonalEmail(value));
      }
      return updated;
    });
  };

  // Real-time calculated live generated email preview
  const generatedEmail = formData.username.trim()
    ? `${formData.username.trim().toLowerCase()}@${formData.role}.com`
    : '';

  // Real-time inline validation flags
  const isUsernameValid = formData.username.trim() && /^[a-zA-Z0-9_]+$/.test(formData.username);
  const isPasswordComplex = formData.password.length >= 8 && /[A-Z]/.test(formData.password) && /[0-9]/.test(formData.password);
  const isPasswordMatch = formData.confirmPassword === formData.password;
  const isPersonalEmailValid = formData.personal_email && !validatePersonalEmail(formData.personal_email);
  const isNameValid = formData.name.trim().length > 0;

  // Form validity check
  const isFormValid = isUsernameValid && isPasswordComplex && isPasswordMatch && isPersonalEmailValid && isNameValid;

  const handleRegister = async (e) => {
    e.preventDefault();
    setErrorMsg('');

    if (!isFormValid) {
      setErrorMsg('Please fill in all required fields correctly.');
      return;
    }

    setLoadingState(true);
    try {
      const payload = {
        username: formData.username.trim().toLowerCase(),
        full_name: formData.name.trim(),
        email: generatedEmail,
        role: formData.role, // Use role from state dynamically!
        password: formData.password,
        personal_email: formData.personal_email.trim().toLowerCase(),
        phone: formData.phone.trim() || null,
        specialization: formData.role === 'doctor' ? (formData.specialization.trim() || null) : null
      };

      const res = await register(payload);
      if (res && res.status === 'success') {
        setShowVerification(true);
      }
    } catch (err) {
      setErrorMsg(err.message || 'Registration failed');
    } finally {
      setLoadingState(false);
    }
  };

  const handleVerify = async (e) => {
    e.preventDefault();
    setErrorMsg('');

    if (verificationCode.length !== 6) {
      setErrorMsg('Code must be exactly 6 digits.');
      return;
    }

    setLoadingState(true);
    try {
      const verifyPayload = {
        username: formData.username.trim().toLowerCase(),
        role: formData.role, // Pass role for proper redirection
        code: verificationCode
      };

      const loggedUser = await verify(verifyPayload);
      if (loggedUser) {
        navigate(formData.role === 'receptionist' ? '/receptionist' : '/doctor');
      }
    } catch (err) {
      setErrorMsg(err.message || 'Verification failed');
    } finally {
      setLoadingState(false);
    }
  };

  if (showVerification) {
    return (
      <AuthShell
        kicker="Account activation"
        title="Verify your clinical profile address."
        description="Please check the recovery email linked to your profile and enter the secure verification code to activate your account."
      >
        <div className="auth-card" style={{ maxWidth: 440, borderRadius: '16px' }}>
          <div style={{
            background: '#ecfdf5', border: '1px solid #a7f3d0',
            borderRadius: '12px', padding: '12px 16px', marginBottom: 16,
            color: '#065f46', fontSize: '0.85rem', fontWeight: 600,
            display: 'flex', alignItems: 'center', gap: 10
          }}>
            <CheckCircle2 size={18} style={{ flexShrink: 0, color: '#10b981' }} />
            <span>If an account exists, a verification code has been sent.</span>
          </div>

          <div className="auth-card-header">
            <div>
              <p className="auth-kicker">Security check</p>
              <h2>Enter Code</h2>
              <p style={{ fontSize: '0.85rem', color: 'var(--clr-text-muted, #6b7280)', marginTop: 8 }}>
                Please check your recovery email and enter the code to authorize.
              </p>
            </div>
          </div>

          {errorMsg && (
            <div className="auth-alert" style={{
              display: 'flex', alignItems: 'center', gap: 10,
              background: 'rgba(239, 68, 68, 0.1)', border: '1px solid rgba(239, 68, 68, 0.2)',
              borderRadius: 'var(--r-md)', padding: 12, marginBottom: 16,
              color: '#ef4444', fontSize: '0.85rem', fontWeight: 500
            }}>
              <AlertCircle size={18} style={{ flexShrink: 0 }} />
              <span>{errorMsg}</span>
            </div>
          )}

          <form onSubmit={handleVerify} className="auth-form">
            <div className="form-group">
              <label className="form-label" htmlFor="verification-code">Verification Code</label>
              <input
                id="verification-code"
                type="text"
                required
                maxLength={6}
                className="form-input"
                style={{ textAlign: 'center', letterSpacing: '0.4rem', fontSize: '1.25rem', fontWeight: 700 }}
                placeholder="000000"
                value={verificationCode}
                onChange={(e) => setVerificationCode(e.target.value.replace(/\D/g, ''))}
              />
            </div>

            <button
              type="submit"
              className="btn btn-primary auth-submit"
              style={{ width: '100%', marginTop: 14, borderRadius: '12px' }}
              disabled={loadingState || verificationCode.length !== 6}
            >
              {loadingState ? 'Verifying...' : <><CheckCircle2 size={18} /> Verify & Activate Account</>}
            </button>
            
            <button
              type="button"
              className="btn btn-ghost"
              style={{ width: '100%', marginTop: 8, borderRadius: '12px' }}
              disabled={loadingState}
              onClick={async () => {
                setLoadingState(true);
                setErrorMsg('');
                try {
                  const payload = {
                    username: formData.username.trim().toLowerCase(),
                    full_name: formData.name.trim(),
                    email: generatedEmail,
                    role: formData.role,
                    password: formData.password,
                    personal_email: formData.personal_email.trim().toLowerCase(),
                    phone: formData.phone.trim() || null,
                    specialization: formData.role === 'doctor' ? (formData.specialization.trim() || null) : null
                  };
                  const res = await register(payload);
                  if (res && res.status === 'success') {
                    alert("If an account exists, a verification code has been sent.");
                  }
                } catch (err) {
                  setErrorMsg(err.message || 'Failed to resend code');
                } finally {
                  setLoadingState(false);
                }
              }}
            >
              Resend Code
            </button>

            <button
              type="button"
              className="btn"
              style={{ width: '100%', marginTop: 8, background: 'none', border: '1px solid var(--clr-border, #e5e7eb)', color: 'var(--clr-text, #1f2937)', borderRadius: '12px' }}
              disabled={loadingState}
              onClick={() => {
                setShowVerification(false);
                setVerificationCode('');
                setErrorMsg('');
              }}
            >
              Cancel & Edit Details
            </button>
          </form>
        </div>
      </AuthShell>
    );
  }

  return (
    <AuthShell
      kicker="New doctor workspace"
      title="Bring a new clinic profile online in minutes."
      description="Create a secure account with role-based access and a clean first session for every member of the care team."
    >
      <div className="auth-card" style={{ maxWidth: 540 }}>
        <Link to="/login" className="auth-back-link">
          <ArrowLeft size={16} /> Back to login
        </Link>

        <div className="auth-card-header">
          <div>
            <p className="auth-kicker">Get started</p>
            <h2>Create account</h2>
          </div>
          <span className="auth-form-icon">
            <UserPlus size={24} />
          </span>
        </div>

        {errorMsg && (
          <div className="auth-alert" style={{
            display: 'flex', alignItems: 'center', gap: 10,
            background: 'rgba(239, 68, 68, 0.1)', border: '1px solid rgba(239, 68, 68, 0.2)',
            borderRadius: 'var(--r-md)', padding: 12, marginBottom: 16,
            color: '#ef4444', fontSize: '0.85rem', fontWeight: 500
          }}>
            <AlertCircle size={18} style={{ flexShrink: 0 }} />
            <span>{errorMsg}</span>
          </div>
        )}

        <form onSubmit={handleRegister} className="auth-form">
          <div className="auth-form-grid" style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14 }}>
            <div className="form-group">
              <label className="form-label" htmlFor="register-name">Full name</label>
              <div className="input-with-icon">
                <User size={18} />
                <input
                  id="register-name"
                  type="text"
                  required
                  className="form-input"
                  style={{ borderRadius: '12px' }}
                  placeholder="Dr. Jane Smith"
                  value={formData.name}
                  onChange={(e) => updateField('name', e.target.value)}
                />
              </div>
            </div>

            <div className="form-group">
              <label className="form-label" htmlFor="register-username">Username</label>
              <div className="input-with-icon">
                <Tag size={18} />
                <input
                  id="register-username"
                  type="text"
                  required
                  className={`form-input ${formData.username && !isUsernameValid ? 'is-invalid' : ''}`}
                  style={{ borderRadius: '12px' }}
                  placeholder="janesmith"
                  value={formData.username}
                  onChange={(e) => updateField('username', e.target.value)}
                />
              </div>
              {formData.username && !isUsernameValid && (
                <span style={{ fontSize: '0.72rem', color: '#ef4444', marginTop: 4, display: 'block' }}>
                  Letters, numbers, or underscores only.
                </span>
              )}
            </div>
          </div>

          <div className="auth-form-grid" style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14, marginTop: 10 }}>
            <div className="form-group">
              <label className="form-label" htmlFor="register-role">Primary role</label>
              <div className="input-with-icon">
                <Stethoscope size={18} />
                <select
                  id="register-role"
                  className="form-input"
                  style={{ borderRadius: '12px' }}
                  value={formData.role}
                  onChange={(e) => updateField('role', e.target.value)}
                >
                  <option value="doctor">Doctor</option>
                  <option value="receptionist">Receptionist</option>
                </select>
              </div>
            </div>

            <div className="form-group">
              <label className="form-label" htmlFor="register-phone">Phone number (Optional)</label>
              <div className="input-with-icon">
                <Phone size={18} />
                <input
                  id="register-phone"
                  type="tel"
                  className="form-input"
                  style={{ borderRadius: '12px' }}
                  placeholder="+1 555-0199"
                  value={formData.phone}
                  onChange={(e) => updateField('phone', e.target.value)}
                />
              </div>
            </div>
          </div>

          {/* Dynamic Specialization Field (Doctor Only) */}
          {formData.role === 'doctor' && (
            <div className="form-group" style={{ marginTop: 10 }}>
              <label className="form-label" htmlFor="register-specialization">Specialization (Optional)</label>
              <div className="input-with-icon">
                <Stethoscope size={18} />
                <input
                  id="register-specialization"
                  type="text"
                  className="form-input"
                  style={{ borderRadius: '12px' }}
                  placeholder="e.g. Orthodontics, Periodontics"
                  value={formData.specialization}
                  onChange={(e) => updateField('specialization', e.target.value)}
                />
              </div>
            </div>
          )}

          {/* Auto-generated Live Clinic Email Preview */}
          <div className="form-group" style={{ marginTop: 10 }}>
            <label className="form-label" htmlFor="register-email">Clinic Email (used for login)</label>
            <div className="input-with-icon">
              <Mail size={18} />
              <input
                id="register-email"
                type="email"
                readOnly
                disabled
                className="form-input"
                style={{ background: 'var(--clr-surface-2, #f3f4f6)', cursor: 'not-allowed', color: 'var(--clr-text-muted, #6b7280)', fontWeight: 600, borderRadius: '12px' }}
                value={generatedEmail || 'Please enter username above...'}
              />
            </div>
          </div>

          {/* Personal Email Field with Instant Validation */}
          <div className="form-group" style={{ marginTop: 10 }}>
            <label className="form-label" htmlFor="register-personal-email">Personal Email (for recovery & recovery codes)</label>
            <div className="input-with-icon">
              <Mail size={18} />
              <input
                id="register-personal-email"
                type="email"
                required
                className={`form-input ${personalEmailError ? 'is-invalid' : ''}`}
                style={{ borderRadius: '12px' }}
                placeholder="you@example.com"
                value={formData.personal_email}
                onChange={(e) => updateField('personal_email', e.target.value)}
              />
            </div>
            {personalEmailError && (
              <span style={{ fontSize: '0.72rem', color: '#ef4444', marginTop: 4, display: 'block' }}>
                Please enter a valid email
              </span>
            )}
          </div>

          <div className="auth-form-grid" style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14, marginTop: 10 }}>
            <div className="form-group">
              <label className="form-label" htmlFor="register-password">Password</label>
              <div className="input-with-icon" style={{ position: 'relative' }}>
                <Lock size={18} />
                <input
                  id="register-password"
                  type={showPassword ? "text" : "password"}
                  required
                  className={`form-input ${formData.password && !isPasswordComplex ? 'is-invalid' : ''}`}
                  style={{ paddingRight: 40, borderRadius: '12px' }}
                  placeholder="Min 8 characters"
                  value={formData.password}
                  onChange={(e) => updateField('password', e.target.value)}
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  aria-label="Toggle password visibility"
                  style={{ position: 'absolute', right: 12, top: '50%', transform: 'translateY(-50%)', background: 'none', border: 'none', cursor: 'pointer', color: 'var(--clr-text-muted, #6b7280)', display: 'flex', alignItems: 'center', padding: 0, zIndex: 10 }}
                >
                  {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                </button>
              </div>
              {formData.password && !isPasswordComplex && (
                <span style={{ fontSize: '0.72rem', color: '#ef4444', marginTop: 4, display: 'block' }}>
                  Must be at least 8 characters, with 1 uppercase letter and 1 number.
                </span>
              )}
            </div>

            <div className="form-group">
              <label className="form-label" htmlFor="register-confirm">Confirm Password</label>
              <div className="input-with-icon" style={{ position: 'relative' }}>
                <Lock size={18} />
                <input
                  id="register-confirm"
                  type={showConfirmPassword ? "text" : "password"}
                  required
                  className={`form-input ${formData.confirmPassword && !isPasswordMatch ? 'is-invalid' : ''}`}
                  style={{ paddingRight: 40, borderRadius: '12px' }}
                  placeholder="Repeat password"
                  value={formData.confirmPassword}
                  onChange={(e) => updateField('confirmPassword', e.target.value)}
                />
                <button
                  type="button"
                  onClick={() => setShowConfirmPassword(!showConfirmPassword)}
                  aria-label="Toggle password visibility"
                  style={{ position: 'absolute', right: 12, top: '50%', transform: 'translateY(-50%)', background: 'none', border: 'none', cursor: 'pointer', color: 'var(--clr-text-muted, #6b7280)', display: 'flex', alignItems: 'center', padding: 0, zIndex: 10 }}
                >
                  {showConfirmPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                </button>
              </div>
              {formData.confirmPassword && !isPasswordMatch && (
                <span style={{ fontSize: '0.72rem', color: '#ef4444', marginTop: 4, display: 'block' }}>
                  Passwords do not match.
                </span>
              )}
            </div>
          </div>

          <div className="auth-agreement" style={{ marginTop: 12 }}>
            <span />
            <p>Your workspace will use secure clinic-level access rules immediately.</p>
          </div>

          <button
            type="submit"
            className="btn btn-primary auth-submit"
            style={{ width: '100%', marginTop: 14 }}
            disabled={loadingState || !isFormValid}
          >
            {loadingState ? 'Creating profile...' : <><CheckCircle2 size={18} /> Create secure account <ArrowRight size={18} style={{ marginLeft: 6 }} /></>}
          </button>

          <p className="auth-switch" style={{ marginTop: 14 }}>
            Already registered? <Link to="/login">Sign in</Link>
          </p>
        </form>
      </div>
    </AuthShell>
  );
}
