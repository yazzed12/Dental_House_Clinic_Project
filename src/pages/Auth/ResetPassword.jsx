import React, { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { Lock, ShieldCheck } from 'lucide-react';

export default function ResetPassword() {
  const [formData, setFormData] = useState({ password: '', confirmPassword: '' });
  const [isSuccess, setIsSuccess] = useState(false);
  const navigate = useNavigate();

  const handleSubmit = (e) => {
    e.preventDefault();
    setIsSuccess(true);
  };

  return (
    <div className="app-layout" style={{ justifyContent: 'center', alignItems: 'center', minHeight: '100vh', background: 'var(--grad-hero)' }}>
      <div className="card-glass" style={{ width: '100%', maxWidth: '440px', padding: 'var(--sp-2xl)' }}>
        
        <div style={{ textAlign: 'center', marginBottom: 'var(--sp-xl)' }}>
           <div className="sidebar-logo-icon" style={{ margin: '0 auto var(--sp-md)', width: 56, height: 56 }}>
             <ShieldCheck size={32} color="#fff" />
           </div>
           <h1 className="page-title" style={{ fontSize: '1.8rem' }}>New Password</h1>
           <p className="page-subtitle">Set your secure password</p>
        </div>

        {!isSuccess ? (
          <form onSubmit={handleSubmit} className="form-group gap-md">
            <div className="form-group">
              <label className="form-label">New Password</label>
              <div style={{ position: 'relative' }}>
                <Lock size={16} style={{ position: 'absolute', left: 12, top: '50%', transform: 'translateY(-50%)', color: 'var(--clr-text-muted)' }} />
                <input 
                  type="password" required className="form-input" style={{ paddingLeft: 40 }}
                  placeholder="••••••••" 
                  value={formData.password} onChange={e => setFormData({...formData, password: e.target.value})}
                />
              </div>
            </div>

            <div className="form-group">
              <label className="form-label">Confirm Password</label>
              <div style={{ position: 'relative' }}>
                <Lock size={16} style={{ position: 'absolute', left: 12, top: '50%', transform: 'translateY(-50%)', color: 'var(--clr-text-muted)' }} />
                <input 
                  type="password" required className="form-input" style={{ paddingLeft: 40 }}
                  placeholder="••••••••" 
                  value={formData.confirmPassword} onChange={e => setFormData({...formData, confirmPassword: e.target.value})}
                />
              </div>
            </div>

            <button type="submit" className="btn btn-primary" style={{ width: '100%', marginTop: 'var(--sp-sm)', padding: '12px' }}>
              Update Password
            </button>
          </form>
        ) : (
          <div style={{ textAlign: 'center' }}>
            <p style={{ color: 'var(--clr-text-secondary)', marginBottom: 'var(--sp-lg)' }}>
              Password successfully updated.
            </p>
            <button className="btn btn-primary" style={{ width: '100%' }} onClick={() => navigate('/login')}>
              Go to Login
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
