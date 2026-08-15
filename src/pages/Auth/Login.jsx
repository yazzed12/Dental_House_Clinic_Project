import React, { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';
import AuthShell from '../../components/AuthShell';
import { Activity, ArrowRight, Building, Eye, EyeOff, Lock, Mail, Stethoscope, Users, AlertCircle } from 'lucide-react';

export default function Login() {
  const [selectedRole, setSelectedRole] = useState('doctor');
  const [showPassword, setShowPassword] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');
  const [loadingState, setLoadingState] = useState(false);
  
  const { login } = useAuth();
  const navigate = useNavigate();

  const roles = [
    { id: 'doctor', label: 'Doctor', icon: Stethoscope },
    { id: 'admin', label: 'Admin', icon: Building },
    { id: 'receptionist', label: 'Reception', icon: Users }
  ];

  const handleLogin = async (e) => {
    e.preventDefault();
    setErrorMsg('');
    
    const email = e.target['login-email'].value.trim();
    const password = e.target['login-password'].value;
    
    if (!email) {
      setErrorMsg('Email address is required.');
      return;
    }
    
    // Reject login if user tries Personal Email
    const personalDomains = ['@gmail.com', '@yahoo.com', '@outlook.com', '@hotmail.com'];
    if (personalDomains.some(domain => email.toLowerCase().endsWith(domain))) {
      setErrorMsg('Login is only allowed using your Clinic Email (e.g. username@doctor.com). Personal emails are strictly for account recovery.');
      return;
    }
    
    setLoadingState(true);
    try {
      // Map demo email to clinic-specific addresses
      let loginEmail = email;
      if (email.toLowerCase() === 'demo@clinic.com') {
        if (selectedRole === 'admin') loginEmail = 'admin@admin.com';
        else if (selectedRole === 'doctor') loginEmail = 'dr__yehia@doctor.com';
        else if (selectedRole === 'receptionist') loginEmail = 'receptionist1@receptionist.com';
      } else if (email.toLowerCase() === 'doctor1@clinic.com' || email.toLowerCase() === 'doctor1@doctor.com') {
        loginEmail = 'dr__yehia@doctor.com';
      }
      
      const loggedUser = await login(selectedRole, loginEmail, password);
      
      if (loggedUser) {
        const actualRole = loggedUser.role;
        if (actualRole === 'admin') navigate('/admin');
        else if (actualRole === 'doctor') navigate('/doctor');
        else if (actualRole === 'receptionist') navigate('/receptionist');
      } else {
        setErrorMsg('Invalid clinic email or password. Please verify your credentials.');
      }
    } catch (err) {
      setErrorMsg(err.message || 'Login failed. Please check your credentials.');
    } finally {
      setLoadingState(false);
    }
  };

  return (
    <AuthShell
      kicker="Clinical access"
      title="One calm entry point for the whole clinic."
      description="Role-aware access for doctors, reception, and admins with the clinical workspace ready the moment you sign in."
    >
      <div className="auth-card auth-card-compact">
        <div className="auth-card-header">
          <div>
            <p className="auth-kicker">Welcome back</p>
            <h2>Sign in</h2>
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

        <form onSubmit={handleLogin} className="auth-form">
          <div className="form-group">
            <label className="form-label">Workspace</label>
            <div className="auth-segmented">
              {roles.map((role) => (
                <button
                  type="button"
                  key={role.id}
                  className={selectedRole === role.id ? 'is-selected' : ''}
                  onClick={() => setSelectedRole(role.id)}
                  aria-pressed={selectedRole === role.id}
                  disabled={loadingState}
                >
                  <role.icon size={17} />
                  <span>{role.label}</span>
                </button>
              ))}
            </div>
          </div>

          <div className="form-group">
            <label className="form-label" htmlFor="login-email">Clinic Email Address</label>
            <div className="input-with-icon">
              <Mail size={18} />
              <input 
                id="login-email" 
                type="email" 
                required 
                className="form-input" 
                style={{ borderRadius: '12px' }}
                placeholder="demo@clinic.com" 
                defaultValue="demo@clinic.com"
                disabled={loadingState}
              />
            </div>
          </div>

          <div className="form-group">
            <label className="form-label" htmlFor="login-password">Password</label>
            <div className="input-with-icon login-password-field">
              <Lock size={18} />
              <input 
                id="login-password" 
                type={showPassword ? "text" : "password"} 
                required 
                className="form-input" 
                placeholder="Enter your password" 
                defaultValue="password123"
                style={{ paddingRight: 52, borderRadius: '12px' }}
                disabled={loadingState}
              />
              <button
                type="button"
                onClick={() => setShowPassword(!showPassword)}
                className="password-visibility-button"
                aria-label={showPassword ? 'Hide password' : 'Show password'}
                aria-pressed={showPassword}
                disabled={loadingState}
              >
                {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
              </button>
            </div>
          </div>

          <div className="auth-row">
            <label className="auth-check">
              <input type="checkbox" defaultChecked disabled={loadingState} />
              <span>Keep me signed in</span>
            </label>
            <Link to="/forgot-password" style={{ pointerEvents: loadingState ? 'none' : 'auto' }}>Forgot password?</Link>
          </div>

          <button type="submit" className="btn btn-primary auth-submit" disabled={loadingState}>
            {loadingState ? 'Opening dashboard...' : <><ArrowRight size={18} style={{ marginRight: 6 }} /> Open dashboard</>}
          </button>

          <p className="auth-switch">
            New to Smart Dental Clinic? <Link to="/register" style={{ pointerEvents: loadingState ? 'none' : 'auto' }}>Create an account</Link>
          </p>
        </form>
      </div>
    </AuthShell>
  );
}
