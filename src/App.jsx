import React from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider, useAuth } from './context/AuthContext';
import { ClinicProvider } from './context/ClinicContext';
import { DataProvider } from './context/DataContext';
import './index.css';

// Layouts
import Layout from './components/Layout';

// Pages
import Login from './pages/Auth/Login';
import Register from './pages/Auth/Register';
import ForgotPassword from './pages/Auth/ForgotPassword';
import ResetPassword from './pages/Auth/ResetPassword';
import AdminDashboard from './pages/Admin/AdminDashboard';
import DoctorDashboard from './pages/Doctor/DoctorDashboard';
import ConsultationFlow from './pages/Doctor/ConsultationFlow';
import ReceptionDashboard from './pages/Receptionist/ReceptionDashboard';
import PatientDashboard from './pages/Patient/PatientDashboard';
import Patients from './pages/Doctor/PatientsPage';
import Appointments from './pages/Appointments';
import Records from './pages/Records';
import Billing from './pages/Billing';
import Settings from './pages/Settings';
import UserManagement from './pages/Admin/UserManagement';
import ConsultationsHistory from './pages/Doctor/ConsultationsHistory';
import PriceList from './pages/Doctor/PriceList';
import LabProductList from './pages/Doctor/LabProductList';
import LabTransactions from './pages/Doctor/LabTransactions';

const ProtectedRoute = ({ children, allowedRoles }) => {
  const { user, loading } = useAuth();
  if (loading) return <div role="status" aria-live="polite">Checking session…</div>;
  if (!user) return <Navigate to="/login" replace />;
  if (allowedRoles && !allowedRoles.includes(user.role)) return <Navigate to="/" replace />;
  
  return children;
};

const RootRedirect = () => {
  const { user, loading } = useAuth();
  if (loading) return <div role="status" aria-live="polite">Checking session…</div>;
  if (!user) return <Navigate to="/login" replace />;
  if (user.role === 'admin') return <Navigate to="/admin" replace />;
  if (user.role === 'doctor') return <Navigate to="/doctor" replace />;
  if (user.role === 'receptionist') return <Navigate to="/receptionist" replace />;
  if (user.role === 'patient') return <Navigate to="/patient" replace />;
  return <Navigate to="/login" replace />;
};

export default function App() {
  return (
    <AuthProvider>
      <DataProvider>
        <ClinicProvider>
          <BrowserRouter>
          <Routes>
            <Route path="/login" element={<Login />} />
            <Route path="/register" element={<Register />} />
            <Route path="/forgot-password" element={<ForgotPassword />} />
            <Route path="/reset-password" element={<ResetPassword />} />
            
            <Route path="/" element={<RootRedirect />} />

            {/* Admin Routes */}
            <Route path="/admin" element={
              <ProtectedRoute allowedRoles={['admin']}>
                <AdminDashboard />
              </ProtectedRoute>
            } />

            {/* Doctor Routes */}
            <Route path="/doctor" element={
              <ProtectedRoute allowedRoles={['doctor']}>
                <DoctorDashboard />
              </ProtectedRoute>
            } />
            <Route path="/doctor/consultation/:id" element={
              <ProtectedRoute allowedRoles={['doctor']}>
                <ConsultationFlow />
              </ProtectedRoute>
            } />
            <Route path="/doctor/consultations-history" element={
              <ProtectedRoute allowedRoles={['doctor', 'admin']}>
                <ConsultationsHistory />
              </ProtectedRoute>
            } />
            <Route path="/doctor/price-list" element={
              <ProtectedRoute allowedRoles={['doctor']}>
                <PriceList />
              </ProtectedRoute>
            } />
            <Route path="/doctor/lab-products" element={<ProtectedRoute allowedRoles={['doctor']}><LabProductList /></ProtectedRoute>} />
            <Route path="/doctor/lab-transactions" element={<ProtectedRoute allowedRoles={['doctor']}><LabTransactions /></ProtectedRoute>} />
            <Route path="/doctor/billing" element={<ProtectedRoute allowedRoles={['doctor']}><Billing /></ProtectedRoute>} />

            {/* Receptionist Routes */}
            <Route path="/receptionist" element={
              <ProtectedRoute allowedRoles={['receptionist']}>
                <ReceptionDashboard />
              </ProtectedRoute>
            } />

            {/* Shared / Specific Sub-pages */}
            <Route path="/admin/users" element={<ProtectedRoute allowedRoles={['admin']}><UserManagement /></ProtectedRoute>} />
            <Route path="/admin/doctors" element={<ProtectedRoute allowedRoles={['admin']}><Navigate to="/admin/users" replace /></ProtectedRoute>} />
            <Route path="/admin/receptionists" element={<ProtectedRoute allowedRoles={['admin']}><Navigate to="/admin/users" replace /></ProtectedRoute>} />
            <Route path="/doctor/patients" element={<ProtectedRoute allowedRoles={['doctor']}><Patients /></ProtectedRoute>} />
            <Route path="/doctor/appointments" element={<ProtectedRoute allowedRoles={['doctor']}><Appointments /></ProtectedRoute>} />
            <Route path="/receptionist/patients" element={<ProtectedRoute allowedRoles={['receptionist']}><Patients /></ProtectedRoute>} />
            <Route path="/receptionist/calendar" element={<ProtectedRoute allowedRoles={['receptionist']}><Appointments /></ProtectedRoute>} />
            <Route path="/patient/records" element={<ProtectedRoute allowedRoles={['patient']}><Records /></ProtectedRoute>} />
            <Route path="/patient/appointments" element={<ProtectedRoute allowedRoles={['patient']}><Appointments /></ProtectedRoute>} />

            {/* Settings Routes */}
            <Route path="/doctor/settings" element={<ProtectedRoute allowedRoles={['doctor']}><Settings /></ProtectedRoute>} />
            <Route path="/admin/settings" element={<ProtectedRoute allowedRoles={['admin']}><Settings /></ProtectedRoute>} />
            <Route path="/receptionist/settings" element={<ProtectedRoute allowedRoles={['receptionist']}><Settings /></ProtectedRoute>} />

            {/* Patient Routes */}
            <Route path="/patient" element={
              <ProtectedRoute allowedRoles={['patient']}>
                <PatientDashboard />
              </ProtectedRoute>
            } />

            {/* Catch-all */}
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </BrowserRouter>
        </ClinicProvider>
      </DataProvider>
    </AuthProvider>
  );
}
