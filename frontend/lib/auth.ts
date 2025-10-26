/**
 * Authentication utilities for token management and storage
 */

const TOKEN_KEY = 'auth_token'
const USER_KEY = 'auth_user'

export interface StoredUser {
  user_id: string
  username: string
}

/**
 * Get stored authentication token from localStorage
 */
export function getStoredToken(): string | null {
  if (typeof window === 'undefined') return null
  return localStorage.getItem(TOKEN_KEY)
}

/**
 * Save authentication token to localStorage
 */
export function setStoredToken(token: string): void {
  if (typeof window === 'undefined') return
  localStorage.setItem(TOKEN_KEY, token)
}

/**
 * Remove authentication token from localStorage
 */
export function clearStoredToken(): void {
  if (typeof window === 'undefined') return
  localStorage.removeItem(TOKEN_KEY)
  localStorage.removeItem(USER_KEY)
}

/**
 * Get stored user info from localStorage
 */
export function getStoredUser(): StoredUser | null {
  if (typeof window === 'undefined') return null

  const userJson = localStorage.getItem(USER_KEY)
  if (!userJson) return null

  try {
    return JSON.parse(userJson)
  } catch (e) {
    return null
  }
}

/**
 * Save user info to localStorage
 */
export function setStoredUser(user: StoredUser): void {
  if (typeof window === 'undefined') return
  localStorage.setItem(USER_KEY, JSON.stringify(user))
}

/**
 * Check if user is authenticated (has token)
 */
export function isAuthenticated(): boolean {
  return !!getStoredToken()
}

/**
 * Clear all authentication data
 */
export function clearAuthData(): void {
  clearStoredToken()
}
