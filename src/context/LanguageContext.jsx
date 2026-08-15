import React, { createContext, useContext, useState, useEffect, useCallback } from 'react';
import translations from '../data/translations';

const LanguageContext = createContext();

export function LanguageProvider({ children }) {
  const [language, setLanguageState] = useState(() => {
    const saved = localStorage.getItem('clinic_lang');
    return saved === 'ar' ? 'ar' : 'en';
  });

  useEffect(() => {
    localStorage.setItem('clinic_lang', language);
    document.documentElement.setAttribute('dir', language === 'ar' ? 'rtl' : 'ltr');
    document.documentElement.setAttribute('lang', language);
  }, [language]);

  const setLanguage = useCallback((lang) => {
    if (lang === 'en' || lang === 'ar') {
      setLanguageState(lang);
    }
  }, []);

  const t = useCallback((key) => {
    const dict = translations[language] || translations.en;
    return dict[key] || translations.en[key] || key;
  }, [language]);

  const formatTime = useCallback((dateStr) => {
    if (!dateStr) return '';
    const now = new Date();
    const date = new Date(dateStr);
    const diffMs = now - date;
    const diffMin = Math.floor(diffMs / 60000);
    const diffHour = Math.floor(diffMs / 3600000);
    const diffDay = Math.floor(diffMs / 86400000);

    if (diffMin < 1) return t('justNow');
    if (diffMin < 60) return t('minAgo').replace('{n}', diffMin);
    if (diffHour < 24) return t('hourAgo').replace('{n}', diffHour);
    return t('dayAgo').replace('{n}', diffDay);
  }, [t]);

  const formatDateTime = useCallback((dateStr, formatStyle = 'full') => {
    if (!dateStr) return '';
    try {
      const date = new Date(dateStr);
      if (isNaN(date.getTime())) return dateStr;
      
      const isArabic = language === 'ar';
      const locale = isArabic ? 'ar' : 'en-US';
      
      if (formatStyle === 'timeOnly') {
        return new Intl.DateTimeFormat(locale, {
          hour: 'numeric',
          minute: '2-digit',
          hour12: true
        }).format(date);
      }
      
      if (formatStyle === 'compact') {
        const datePart = new Intl.DateTimeFormat(locale, {
          month: 'short',
          day: 'numeric'
        }).format(date);
        const timePart = new Intl.DateTimeFormat(locale, {
          hour: 'numeric',
          minute: '2-digit',
          hour12: true
        }).format(date);
        return isArabic ? `${datePart}، ${timePart}` : `${datePart}, ${timePart}`;
      }
      
      // Default / Full: e.g. "May 17, 2026 — 4:40 PM"
      const datePart = new Intl.DateTimeFormat(locale, {
        year: 'numeric',
        month: 'short',
        day: 'numeric'
      }).format(date);
      const timePart = new Intl.DateTimeFormat(locale, {
        hour: 'numeric',
        minute: '2-digit',
        hour12: true
      }).format(date);
      
      return `${datePart} — ${timePart}`;
    } catch (e) {
      console.error("Error formatting date:", e);
      return dateStr;
    }
  }, [language]);

  return (
    <LanguageContext.Provider value={{ language, setLanguage, t, formatTime, formatDateTime }}>
      {children}
    </LanguageContext.Provider>
  );
}

export const useLanguage = () => {
  const context = useContext(LanguageContext);
  if (!context) throw new Error('useLanguage must be used within LanguageProvider');
  return context;
};
