import React, { createContext, useContext, useState, useEffect, useRef } from 'react';
import { authService } from '../services/authService.js';

const AuthContext = createContext();

export function AuthProvider({ children }) {
  // Roles: 'admin', 'doctor', 'receptionist', 'patient'
  const [user, setUser] = useState(null); 
  const [loading, setLoading] = useState(true);
  const operationGeneration = useRef(0);

  useEffect(() => {
    let active = true;
    const unsubscribe = authService.onAuthStateChange((nextUser) => {
      if (!active) return;
      operationGeneration.current += 1;
      setUser(nextUser);
      setLoading(false);
    });
    const restoreGeneration = ++operationGeneration.current;
    authService.loadApplicationUser()
      .then((nextUser) => {
        if (active && restoreGeneration === operationGeneration.current) setUser(nextUser);
      })
      .catch(() => {
        if (active && restoreGeneration === operationGeneration.current) setUser(null);
      })
      .finally(() => {
        if (active && restoreGeneration === operationGeneration.current) setLoading(false);
      });
    return () => {
      active = false;
      unsubscribe();
    };
  }, []);

  const login = async (role, username = 'doctor1', password = 'password123') => {
    const loginGeneration = ++operationGeneration.current;
    try {
      const userData = await authService.signIn(username, password, role);
      if (loginGeneration === operationGeneration.current) {
        setUser(userData);
        setLoading(false);
      }
      return userData;
    } catch (err) {
      console.error("Auth error:", err);
      return null;
    }
  };
  
  const register = async (payload) => {
    try {
      return await authService.register(payload);
    } catch (err) {
      console.error("Registration error:", err);
      throw err;
    }
  };

  const verify = async (payload) => {
    try {
      const userData = await authService.verify(payload);
      setUser(userData);
      return userData;
    } catch (err) {
      console.error("Verification error:", err);
      throw err;
    }
  };
  
  const logout = async () => {
    const logoutGeneration = ++operationGeneration.current;
    try {
      await authService.signOut();
    } finally {
      if (logoutGeneration === operationGeneration.current) {
        setUser(null);
        setLoading(false);
      }
    }
  };

  const refreshProfile = async () => {
    const refreshGeneration = ++operationGeneration.current;
    const nextUser = await authService.loadApplicationUser();
    if (refreshGeneration === operationGeneration.current) setUser(nextUser);
    return nextUser;
  };

  return (
    <AuthContext.Provider value={{ user, login, logout, register, verify, refreshProfile, loading, authProvider: authService.provider }}>
      {children}
    </AuthContext.Provider>
  );
}

export const useAuth = () => useContext(AuthContext);
