"use client"

/**
 * Authentication context for managing global auth state
 * Provides login, logout, and user information across the app
 */

import React, { createContext, useContext, useState, useEffect, useCallback } from 'react'
import { useRouter } from 'next/navigation'
import { apiClient } from './api-client'
import {
  getStoredToken,
  setStoredToken,
  clearStoredToken,
  getStoredUser,
  setStoredUser,
  StoredUser,
} from './auth'

interface AuthContextType {
  user: StoredUser | null
  isAuthenticated: boolean
  isLoading: boolean
  login: (username: string, password: string) => Promise<void>
  register: (username: string, password: string) => Promise<void>
  logout: () => Promise<void>
  refreshUser: () => Promise<void>
}

const AuthContext = createContext<AuthContextType | undefined>(undefined)

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<StoredUser | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const router = useRouter()

  // Initialize auth state from localStorage
  useEffect(() => {
    const initAuth = async () => {
      const token = getStoredToken()
      const storedUser = getStoredUser()

      if (token && storedUser) {
        // Verify token is still valid by fetching user info
        try {
          const currentUser = await apiClient.getCurrentUser()
          setUser({
            user_id: currentUser.user_id,
            username: currentUser.username,
          })
          setStoredUser({
            user_id: currentUser.user_id,
            username: currentUser.username,
          })
        } catch (error) {
          // Token expired or invalid
          clearStoredToken()
          setUser(null)
        }
      }

      setIsLoading(false)
    }

    initAuth()
  }, [])

  const login = useCallback(
    async (username: string, password: string) => {
      try {
        const response = await apiClient.login(username, password)

        // Store token and user info
        setStoredToken(response.token)
        const userData: StoredUser = {
          user_id: response.user_id,
          username: response.username,
        }
        setStoredUser(userData)
        setUser(userData)

        // Redirect to home
        router.push('/')
      } catch (error) {
        throw error
      }
    },
    [router]
  )

  const register = useCallback(
    async (username: string, password: string) => {
      try {
        const response = await apiClient.register(username, password)

        // Auto-login after registration
        setStoredToken(response.token)
        const userData: StoredUser = {
          user_id: response.user_id,
          username: response.username,
        }
        setStoredUser(userData)
        setUser(userData)

        // Redirect to home
        router.push('/')
      } catch (error) {
        throw error
      }
    },
    [router]
  )

  const logout = useCallback(async () => {
    try {
      await apiClient.logout()
    } catch (error) {
      // Continue with logout even if API call fails
      console.error('Logout API call failed:', error)
    } finally {
      clearStoredToken()
      setUser(null)
      router.push('/login')
    }
  }, [router])

  const refreshUser = useCallback(async () => {
    try {
      const currentUser = await apiClient.getCurrentUser()
      const userData: StoredUser = {
        user_id: currentUser.user_id,
        username: currentUser.username,
      }
      setStoredUser(userData)
      setUser(userData)
    } catch (error) {
      // If refresh fails, clear auth
      clearStoredToken()
      setUser(null)
    }
  }, [])

  const value: AuthContextType = {
    user,
    isAuthenticated: !!user,
    isLoading,
    login,
    register,
    logout,
    refreshUser,
  }

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider')
  }
  return context
}
