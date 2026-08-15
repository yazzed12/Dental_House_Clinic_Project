import React, { createContext, useCallback, useContext, useState, useEffect, useRef } from 'react';
import { useAuth } from './AuthContext';
import { getClinicSettings, updateClinicSettings as saveClinicInformation } from '../services/clinicSettingsApi.js';

const ClinicContext = createContext();
const clinicReaders = new Set(['doctor', 'admin', 'receptionist']);

export function ClinicProvider({ children }) {
  const { user, loading: authLoading } = useAuth();
  const [clinicSettings, setClinicSettings] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const generation = useRef(0);

  const refreshClinicSettings = useCallback(async () => {
    const request = ++generation.current;
    if (!user || !clinicReaders.has(user.role)) {
      setClinicSettings(null); setError(''); setLoading(false); return null;
    }
    setLoading(true); setError('');
    try {
      const data = await getClinicSettings();
      if (request === generation.current) setClinicSettings(data);
      return data;
    } catch (err) {
      if (request === generation.current) { setClinicSettings(null); setError(err.message || 'Clinic Information could not be loaded.'); }
      throw err;
    } finally {
      if (request === generation.current) setLoading(false);
    }
  }, [user]);

  useEffect(() => {
    if (authLoading) return undefined;
    refreshClinicSettings().catch(() => {});
    return () => { generation.current += 1; };
  }, [authLoading, refreshClinicSettings]);

  const updateClinicSettings = async (newData) => {
    try {
      const data = await saveClinicInformation(newData);
      setClinicSettings(data);
      setError('');
      return data;
    } catch (err) {
      console.error("Update clinic settings error:", err);
      setError(err.message || 'Failed to update clinic settings');
      throw err;
    }
  };

  return (
    <ClinicContext.Provider value={{ clinicSettings, updateClinicSettings, loading, error, refreshClinicSettings }}>
      {children}
    </ClinicContext.Provider>
  );
}

export const useClinic = () => useContext(ClinicContext);
