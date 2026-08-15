import React, { useEffect, useRef, useState } from 'react';
import { useNotifications } from '../hooks/useNotifications';
import { useAuth } from '../context/AuthContext';
import { useTheme } from '../context/ThemeContext';
import { useLanguage } from '../context/LanguageContext';
import {
  Bell, Sun, Moon, Globe, LogOut,
  CheckCheck
} from 'lucide-react';

export default function Topbar({ pageTitle, pageSubtitle }) {
  const { user, logout, loading: authLoading, authProvider } = useAuth();
  const {
    notifications, unreadCount, loading, error,
    markAsRead, markAllAsRead, refresh: retryNotifications, refreshIfStale,
  } = useNotifications({ user, authLoading, authProvider });
  const { theme, toggleTheme } = useTheme();
  const { language, setLanguage, t, formatTime } = useLanguage();

  const [isProfileOpen, setIsProfileOpen] = useState(false);
  const [isNotificationsOpen, setIsNotificationsOpen] = useState(false);
  const [isLangOpen, setIsLangOpen] = useState(false);

  const notificationsRef = useRef(null);
  const profileRef = useRef(null);
  const langRef = useRef(null);

  // Close dropdowns on outside click
  useEffect(() => {
    const onClickOutside = (event) => {
      if (notificationsRef.current && !notificationsRef.current.contains(event.target)) {
        setIsNotificationsOpen(false);
      }
      if (profileRef.current && !profileRef.current.contains(event.target)) {
        setIsProfileOpen(false);
      }
      if (langRef.current && !langRef.current.contains(event.target)) {
        setIsLangOpen(false);
      }
    };
    document.addEventListener('mousedown', onClickOutside);
    return () => document.removeEventListener('mousedown', onClickOutside);
  }, []);



  const getRoleName = (role) => {
    const roleMap = { doctor: 'roleDoctor', admin: 'roleAdmin', receptionist: 'roleReceptionist', patient: 'rolePatient' };
    return t(roleMap[role] || 'roleDoctor');
  };

  const getNotifIcon = (type) => {
    if (type === 'success' || type === 'appointment_arrived') return <CheckCheck size={14} />;
    if (type === 'warning') return <Bell size={14} />;
    return <Bell size={14} />;
  };

  const getNotifColor = (type) => {
    if (type === 'success' || type === 'appointment_arrived') return 'var(--clr-primary)';
    if (type === 'warning') return 'var(--clr-warning)';
    return 'var(--clr-primary)';
  };

  const userName = user?.name || 'User';
  const userRole = user?.role ? getRoleName(user.role) : 'Guest';
  const displayRole = user?.specialization ? `${userRole} • ${user?.specialization}` : userRole;
  const userEmail = user?.email || '';
  const userInitials = userName.split(' ').map(n => n[0]).join('').toUpperCase().slice(0, 2);

  return (
    <div className="topbar">
      <div className="topbar-title">
        <h1>{pageTitle || t('dashboard')}</h1>
        {pageSubtitle && <p>{pageSubtitle}</p>}
      </div>


      <div className="topbar-actions">
        {/* Language Toggle */}
        <div className="dropdown-wrap" ref={langRef}>
          <button
            className="icon-btn"
            onClick={() => setIsLangOpen(prev => !prev)}
            title={t('language')}
          >
            <Globe size={18} />
          </button>
          {isLangOpen && (
            <div className="dropdown-menu lang-menu">
              <div className="dropdown-header">{t('language')}</div>
              <button
                className={`dropdown-item ${language === 'en' ? 'is-active' : ''}`}
                onClick={() => { setLanguage('en'); setIsLangOpen(false); }}
              >
                <span>🇺🇸</span> English
              </button>
              <button
                className={`dropdown-item ${language === 'ar' ? 'is-active' : ''}`}
                onClick={() => { setLanguage('ar'); setIsLangOpen(false); }}
              >
                <span>🇸🇦</span> العربية
              </button>
            </div>
          )}
        </div>

        {/* Dark Mode Toggle */}
        <button className="icon-btn" onClick={toggleTheme} title={theme === 'dark' ? t('lightMode') : t('darkMode')}>
          {theme === 'dark' ? <Sun size={18} /> : <Moon size={18} />}
        </button>

        {/* Notifications */}
        <div className="dropdown-wrap" ref={notificationsRef}>
          <button className="icon-btn" onClick={() => setIsNotificationsOpen((prev) => {
            const next = !prev;
            if (next) void refreshIfStale();
            return next;
          })} title={t('notifications')}>
            <Bell size={18} />
            {unreadCount > 0 && <span className="notif-badge">{unreadCount > 9 ? '9+' : unreadCount}</span>}
          </button>
          {isNotificationsOpen && (
            <div className="dropdown-menu notifications-menu">
              <div className="dropdown-header notifications-header">
                <span>{t('notifications')}</span>
                {unreadCount > 0 && (
                  <button className="mark-all-btn" onClick={markAllAsRead}>{t('markAllRead')}</button>
                )}
              </div>
              {loading && notifications.length === 0 && <div className="dropdown-empty">...</div>}
              {error && (
                <div className="dropdown-empty">
                  <div>{error}</div>
                  <button className="btn btn-secondary btn-sm" onClick={retryNotifications}>Retry</button>
                </div>
              )}
              {!loading && !error && notifications.length === 0 && <div className="dropdown-empty">{t('noNotifications')}</div>}
              {notifications.map((item) => (
                <button key={item.id} className={`notification-item ${item.read_at == null ? 'is-unread' : ''}`} onClick={() => markAsRead(item.id)}>
                  <div className="notification-row">
                    <div className="notification-icon-wrap" style={{ color: getNotifColor(item.type) }}>
                      {getNotifIcon(item.type)}
                    </div>
                    <div className="notification-content">
                      <div className="notification-title">{item.title}</div>
                      <div className="notification-body">{item.body}</div>
                      <div className="notification-time">{formatTime(item.created_at)}</div>
                    </div>
                    {item.read_at == null && <div className="notification-unread-dot" />}
                  </div>
                </button>
              ))}
            </div>
          )}
        </div>

        <div className="topbar-divider" />

        {/* Profile */}
        <div className="dropdown-wrap" ref={profileRef}>
          <button className="topbar-user profile-trigger" onClick={() => setIsProfileOpen((prev) => !prev)} title={t('profile')}>
            <div className="topbar-user-meta">
              <div className="topbar-user-name">{userName}</div>
              <div className="topbar-user-role">{displayRole}</div>
            </div>
            <div className="avatar-wrap">
              <div className="avatar">{userInitials}</div>
              <span className="status-dot online" />
            </div>
          </button>
          {isProfileOpen && (
            <div className="dropdown-menu profile-menu">
              <div className="profile-panel">
                <div className="profile-panel-header">
                  <div className="profile-avatar-lg">{userInitials}</div>
                  <div>
                    <div className="profile-panel-name">{userName}</div>
                    <div className="profile-panel-role-badge">{displayRole}</div>
                  </div>
                </div>
                {userEmail && <div className="profile-panel-email">{userEmail}</div>}
              </div>
              <button className="dropdown-item danger" onClick={logout}>
                <LogOut size={16} />
                {t('signOut')}
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
