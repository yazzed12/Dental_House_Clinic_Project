import React, { createContext, useContext, useState, useEffect, useCallback, useRef } from 'react';
import { useAuth } from './AuthContext.jsx';
import { markFinishedAppointment } from '../services/appointmentLifecycle';
import * as patientApi from '../services/patientApi.js';
import * as appointmentApi from '../services/appointmentApi.js';
import * as staffApi from '../services/staffApi.js';
import { listRecords } from '../services/recordsApi.js';
import { getDashboard } from '../services/dashboardApi.js';
import { canFetchAppointments, canFetchDoctors, canFetchPatients, isCurrentDataRequest } from './sessionLifecycle.js';

const DataContext = createContext();

const EMPTY_STATS = {
  totalPatients: { value: 0, change: 0, label: 'Total Patients' },
  todayAppts: { value: 0, change: 0, label: "Today's Appointments" },
  activeDoctors: { value: 0, change: 0, label: 'Active Doctors' },
  bedOccupancy: { value: '0%', change: 0, label: 'Bed Occupancy' },
  revenue: { value: '$0', change: 0, label: 'Monthly Revenue' },
};

export function DataProvider({ children }) {
  const { user, loading: authLoading, authProvider } = useAuth();
  const [patients, setPatients] = useState([]);
  const [patientsLoading, setPatientsLoading] = useState(false);
  const [patientsError, setPatientsError] = useState(null);
  const [patientsOwnerId, setPatientsOwnerId] = useState(null);
  const [appointments, setAppointments] = useState([]);
  const [appointmentsLoading, setAppointmentsLoading] = useState(false);
  const [appointmentsError, setAppointmentsError] = useState(null);
  const [appointmentsOwnerId, setAppointmentsOwnerId] = useState(null);
  const [doctors, setDoctors] = useState([]);
  const [doctorsLoading, setDoctorsLoading] = useState(false);
  const [doctorsError, setDoctorsError] = useState(null);
  const [doctorsOwnerId, setDoctorsOwnerId] = useState(null);
  const [receptionists, setReceptionists] = useState([]);
  const [records, setRecords] = useState([]);
  const [stats, setStats] = useState(EMPTY_STATS);
  const requestGeneration = useRef(0);
  const currentUserId = useRef(null);
  const isSupabaseMode = useRef(false);
  const canFetchDoctorsRef = useRef(false);
  const canFetchAppointmentsRef = useRef(false);

  const clearUserScopedData = useCallback(() => {
    setPatients([]);
    setPatientsLoading(false);
    setPatientsError(null);
    setPatientsOwnerId(null);
    setAppointments([]);
    setAppointmentsLoading(false);
    setAppointmentsError(null);
    setAppointmentsOwnerId(null);
    setDoctors([]);
    setDoctorsLoading(false);
    setDoctorsError(null);
    setDoctorsOwnerId(null);
    setReceptionists([]);
    setRecords([]);
    setStats(EMPTY_STATS);
  }, []);

  const fetchBackendData = useCallback(async (
    generation = ++requestGeneration.current,
    expectedUserId = currentUserId.current,
    includePatients = isSupabaseMode.current,
    includeDoctors = canFetchDoctorsRef.current,
    includeAppointments = canFetchAppointmentsRef.current,
  ) => {
    if (!expectedUserId) return;
    if (includePatients) {
      setPatientsLoading(true);
      setPatientsError(null);
    }
    if (includeDoctors) {
      setDoctorsLoading(true);
      setDoctorsError(null);
    }
    if (includeAppointments) {
      setAppointmentsLoading(true);
      setAppointmentsError(null);
    }
    try {
      const results = await Promise.allSettled([
        includePatients ? patientApi.listPatients() : Promise.resolve(null),
        includeAppointments ? appointmentApi.listAppointments() : Promise.resolve(null),
        includeDoctors ? staffApi.listDoctors() : Promise.resolve(null),
        staffApi.listReceptionists(),
        listRecords(),
        getDashboard(),
      ]);
      if (!isCurrentDataRequest({
        generation,
        currentGeneration: requestGeneration.current,
        expectedUserId,
        currentUserId: currentUserId.current,
      })) return;
      const [patientsResult, appointmentsResult, doctorsResult, receptionistsResult, recordsResult, dashboardResult] = results;
      if (includePatients) {
        if (patientsResult.status === 'fulfilled') {
          setPatients(patientsResult.value);
          setPatientsError(null);
        } else {
          setPatients([]);
          setPatientsError(patientsResult.reason?.message || 'Failed to fetch patients');
        }
        setPatientsOwnerId(expectedUserId);
        setPatientsLoading(false);
      }
      if (includeAppointments) {
        if (appointmentsResult.status === 'fulfilled') {
          setAppointments(appointmentsResult.value);
          setAppointmentsError(null);
        } else {
          setAppointments([]);
          setAppointmentsError(appointmentsResult.reason?.message || 'Failed to fetch appointments');
        }
        setAppointmentsOwnerId(expectedUserId);
        setAppointmentsLoading(false);
      }
      if (includeDoctors) {
        if (doctorsResult.status === 'fulfilled') {
          setDoctors(doctorsResult.value);
          setDoctorsError(null);
        } else {
          setDoctors([]);
          setDoctorsError(doctorsResult.reason?.message || 'Failed to fetch Doctors');
        }
        setDoctorsOwnerId(expectedUserId);
        setDoctorsLoading(false);
      }
      if (receptionistsResult.status === 'fulfilled') setReceptionists(receptionistsResult.value);
      if (recordsResult.status === 'fulfilled') setRecords(recordsResult.value);
      if (dashboardResult.status === 'fulfilled') {
        const sData = dashboardResult.value;
        const activeDoctorCount = includeDoctors && doctorsResult.status === 'fulfilled'
          ? doctorsResult.value.length
          : 0;
        setStats({
          totalPatients: { value: sData.totalPatients || 0, change: 0, label: 'Total Patients' },
          todayAppts: { value: sData.todayAppointments || 0, change: 0, label: "Today's Appointments" },
          activeDoctors: { value: activeDoctorCount, change: 0, label: 'Active Doctors' },
          bedOccupancy: { value: '76%', change: 0, label: 'Bed Occupancy' },
          revenue: { value: '$84.2K', change: 0, label: 'Monthly Revenue' },
        });
      }
    } catch (err) {
      if (includePatients && isCurrentDataRequest({
        generation,
        currentGeneration: requestGeneration.current,
        expectedUserId,
        currentUserId: currentUserId.current,
      })) {
        setPatients([]);
        setPatientsError(err.message || 'Failed to fetch patients');
        setPatientsOwnerId(expectedUserId);
        setPatientsLoading(false);
      }
      if (includeDoctors && isCurrentDataRequest({
        generation,
        currentGeneration: requestGeneration.current,
        expectedUserId,
        currentUserId: currentUserId.current,
      })) {
        setDoctors([]);
        setDoctorsError(err.message || 'Failed to fetch Doctors');
        setDoctorsOwnerId(expectedUserId);
        setDoctorsLoading(false);
      }
      if (includeAppointments && isCurrentDataRequest({
        generation,
        currentGeneration: requestGeneration.current,
        expectedUserId,
        currentUserId: currentUserId.current,
      })) {
        setAppointments([]);
        setAppointmentsError(err.message || 'Failed to fetch appointments');
        setAppointmentsOwnerId(expectedUserId);
        setAppointmentsLoading(false);
      }
      console.error('Error fetching data from backend:', err);
    }
  }, []);

  useEffect(() => {
    if (authLoading) return undefined;

    const generation = ++requestGeneration.current;
    currentUserId.current = user?.id || null;
    const patientsReady = canFetchPatients({ authLoading, user, authProvider });
    const doctorsReady = canFetchDoctors({ authLoading, user, authProvider });
    const appointmentsReady = canFetchAppointments({ authLoading, user, authProvider });
    isSupabaseMode.current = patientsReady;
    canFetchDoctorsRef.current = doctorsReady;
    canFetchAppointmentsRef.current = appointmentsReady;
    // Clearing user-scoped clinical data must happen in the same auth transition.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    clearUserScopedData();

    if (!user) return undefined;
    // Admin pages hydrate their global Supabase RPCs directly. Do not launch
    // the legacy clinical/staff background request bundle for Admin sessions.
    if (user.role === 'admin') return undefined;
    const timer = setTimeout(() => {
      fetchBackendData(generation, user.id, patientsReady, doctorsReady, appointmentsReady);
    }, 0);
    return () => {
      clearTimeout(timer);
      requestGeneration.current += 1;
    };
  }, [authLoading, authProvider, clearUserScopedData, fetchBackendData, user]);

  const addPatient = async (patient) => {
    try {
      const newPatient = await patientApi.createPatient(patient);
      setPatients(prev => [...prev, newPatient]);
      return newPatient;
    } catch (err) {
      console.error(err);
    }
    return null;
  };

  const deletePatient = async (id) => {
    try {
      const data = await patientApi.deletePatient(id);
      setPatients(prev => prev.filter(p => p.id !== id));
      fetchBackendData(); // Refresh stats instantly
      return { success: true, action: data.action, message: data.message };
    } catch (err) {
      console.error(err);
      return { success: false, error: err.message || 'Network error occurred' };
    }
  };

  const addAppointment = async (appt) => {
    try {
      const newAppt = await appointmentApi.createAppointment(appt);
      setAppointments(prev => [...prev, newAppt]);
      fetchBackendData(); // Refreshes dashboard stats
      return newAppt;
    } catch (err) {
      console.error(err);
    }
    return null;
  };

  const updateAppointmentStatus = async (id, status) => {
    try {
      const updated = await appointmentApi.updateAppointmentStatus(id, status);
      setAppointments(prev => prev.map(a => a.id === id ? { ...a, ...updated } : a));
      fetchBackendData();
    } catch (err) {
      console.error(err);
      throw err;
    }
  };

  const markAppointmentArrived = async (id) => {
    try {
      const updated = await appointmentApi.markAppointmentArrived(id);
      setAppointments(prev => prev.map(a => a.id === id ? { ...a, ...updated } : a));
      return updated;
    } catch (err) {
      console.error(err);
      throw err;
    }
  };

  const deleteAppointment = async (id) => {
    try {
      await appointmentApi.deleteAppointment(id);
      setAppointments(prev => prev.filter(a => a.id !== id));
      fetchBackendData();
    } catch (err) {
      console.error(err);
      throw err;
    }
  };

  const updateAppointment = async (id, updates) => {
    // Optimistic UI
    setAppointments(prev => prev.map(a => a.id === id ? { ...a, ...updates } : a));
    try {
      const updated = await appointmentApi.updateAppointment(id, updates);
      setAppointments(prev => prev.map(a => a.id === id ? { ...a, ...updated } : a));
      fetchBackendData();
      return updated;
    } catch (err) {
      console.error('Error updating appointment:', err);
      throw err;
    }
  };

  const fetchPatientById = async (id) => {
    try {
      return await patientApi.getPatient(id);
    } catch (err) {
      console.error('Error fetching patient by ID:', err);
    }
    return null;
  };

  const updatePatient = async (id, updates) => {
    setPatients(prev => prev.map(p => p.id === id ? { ...p, ...updates } : p));
    try {
      const result = await patientApi.updatePatient(id, updates);
      if (result.status === 'success') {
        setPatients(prev => prev.map(p => p.id === id ? { ...p, ...result.patient } : p));
        fetchBackendData();
        return result.patient;
      }
    } catch (err) {
      console.error('Error updating patient:', err);
    }
    return null;
  };

  const completeAppointmentByPatient = async (patientId, appointmentId = null) => {
    try {
      const result = await appointmentApi.finishAppointmentByPatient(patientId, appointmentId);
      const today = new Date().toISOString().split('T')[0];
      setAppointments(prev => markFinishedAppointment(prev, {
        patientId,
        appointmentId,
        today,
      }));
      await fetchBackendData();
      return result;
    } catch (err) {
      console.error("API Error finishing appointment:", err);
      throw err;
    }
  };

  const addStaff = async (staffData) => {
    try {
      await staffApi.createStaff(staffData);
      fetchBackendData();
      return { success: true };
    } catch (err) {
      console.error(err);
      return { success: false, error: err.message || 'Network error' };
    }
  };

  const updateStaff = async (id, updates) => {
    try {
      await staffApi.updateStaff(id, updates);
      fetchBackendData();
      return { success: true };
    } catch (err) {
      console.error(err);
      return { success: false, error: err.message || 'Network error' };
    }
  };

  const deleteStaff = async (id) => {
    try {
      await staffApi.deleteStaff(id);
      fetchBackendData();
      return { success: true };
    } catch (err) {
      console.error(err);
    }
    return { success: false };
  };

  const value = {
    patients,
    patientsLoading: patientsLoading || canFetchPatients({ authLoading, user, authProvider }) && patientsOwnerId !== user.id,
    patientsError,
    appointments,
    appointmentsLoading: appointmentsLoading || canFetchAppointments({ authLoading, user, authProvider }) && appointmentsOwnerId !== user.id,
    appointmentsError,
    doctors,
    doctorsLoading: doctorsLoading || canFetchDoctors({ authLoading, user, authProvider }) && doctorsOwnerId !== user.id,
    doctorsError,
    receptionists,
    records,
    stats,
    addPatient,
    fetchPatientById,
    updatePatient,
    deletePatient,
    addAppointment,
    updateAppointment,
    updateAppointmentStatus,
    markAppointmentArrived,
    deleteAppointment,
    completeAppointmentByPatient,
    addStaff,
    updateStaff,
    deleteStaff,
    refreshData: fetchBackendData
  };

  return (
    <DataContext.Provider value={value}>
      {children}
    </DataContext.Provider>
  );
}

export const useData = () => {
  const context = useContext(DataContext);
  if (!context) throw new Error('useData must be used within DataProvider');
  return context;
};
