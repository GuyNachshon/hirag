"use client"

/**
 * Protected route wrapper that redirects to login if not authenticated
 */

import { useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { useAuth } from './auth-context'

export function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const { isAuthenticated, isLoading } = useAuth()
  const router = useRouter()

  useEffect(() => {
    if (!isLoading && !isAuthenticated) {
      router.push('/login')
    }
  }, [isAuthenticated, isLoading, router])

  // Show loading state while checking authentication
  if (isLoading) {
    return (
      <main className="flex-1 flex items-center justify-center">
        <div className="text-center">
          <div className="w-12 h-12 border-4 border-primary border-t-transparent rounded-full animate-spin mx-auto mb-4"></div>
          <p className="text-muted-foreground">טוען...</p>
        </div>
      </main>
    )
  }

  // If not authenticated, don't render children (redirect will happen)
  if (!isAuthenticated) {
    return null
  }

  return <>{children}</>
}
