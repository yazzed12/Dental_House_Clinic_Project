import React from 'react';
import { NavLink } from 'react-router-dom';
import {
  Activity, LayoutDashboard, Users, CalendarDays,
  Settings, UserCog, ClipboardList, ReceiptText, Package, Landmark
} from 'lucide-react';
import { useAuth } from '../context/AuthContext';
import { useLanguage } from '../context/LanguageContext';
import { useClinic } from '../context/ClinicContext';

const roleLinks = {
  doctor: [
    { path: '/doctor', icon: LayoutDashboard, labelKey: 'dashboard' },
    { path: '/doctor/appointments', icon: CalendarDays, labelKey: 'appointments' },
    { path: '/doctor/patients', icon: Users, labelKey: 'patients' },
    { path: '/doctor/consultations-history', icon: ClipboardList, labelKey: 'consultationHistory' },
    { path: '/doctor/price-list', icon: ReceiptText, label: 'Price List' },
    { path: '/doctor/lab-products', icon: Package, label: 'Lab Product List' },
    { path: '/doctor/lab-transactions', icon: Landmark, label: 'Lab Transactions' },
    { path: '/doctor/billing', icon: ReceiptText, label: 'Billing' },
    { path: '/doctor/settings', icon: Settings, labelKey: 'settings' },
  ],
  admin: [
    { path: '/admin', icon: LayoutDashboard, labelKey: 'dashboard' },
    { path: '/admin/users', icon: Users, label: 'User Management' },
    { path: '/admin/settings', icon: Settings, labelKey: 'settings' },
  ],
  receptionist: [
    { path: '/receptionist', icon: LayoutDashboard, labelKey: 'dashboard' },
    { path: '/receptionist/patients', icon: Users, labelKey: 'patients' },
    { path: '/receptionist/calendar', icon: CalendarDays, labelKey: 'calendar' },
    { path: '/receptionist/settings', icon: Settings, labelKey: 'settings' },
  ],
  patient: [
    { path: '/patient', icon: LayoutDashboard, labelKey: 'dashboard' },
    { path: '/patient/appointments', icon: CalendarDays, labelKey: 'appointments' },
    { path: '/patient/records', icon: UserCog, labelKey: 'records' },
  ],
};

export default function Sidebar() {
  const { user } = useAuth();
  const { t } = useLanguage();
  const { clinicSettings } = useClinic();

  const role = user?.role || 'doctor';
  const links = roleLinks[role] || roleLinks.doctor;
  const basePath = `/${role}`;
  
  const clinicName = clinicSettings?.name || t('clinicName');
  // Use a short version of the address or just keep clinicSub if it doesn't make sense. We'll stick to a default subtitle if none.
  const clinicSub = t('clinicSub');

  return (
    <div className="sidebar">
      <div className="sidebar-logo">
        <div className="sidebar-logo-icon">
          <Activity size={20} color="#fff" />
        </div>
        <div>
          <div className="sidebar-logo-text">{clinicName}</div>
          <div className="sidebar-logo-sub text-gradient-teal">{clinicSub}</div>
        </div>
      </div>
      
      <div className="sidebar-nav">
        <div className="sidebar-section-label">{t('workspace')}</div>
        {links.map((link) => (
          <NavLink 
            key={link.path} 
            to={link.path} 
            end={link.path === basePath}
            className={({ isActive }) => `nav-item ${isActive ? 'active' : ''}`}
          >
            <link.icon size={18} className="nav-icon" />
            <span>{link.label || t(link.labelKey)}</span>
          </NavLink>
        ))}
      </div>
    </div>
  );
}
