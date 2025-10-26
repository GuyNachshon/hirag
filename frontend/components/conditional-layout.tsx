"use client"

import { usePathname } from 'next/navigation'
import { AppLayout } from './app-layout'

/**
 * Conditional layout wrapper that only shows AppLayout for authenticated pages
 * Login and register pages get a clean layout without sidebars
 */
export function ConditionalLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname()

  // Pages that should NOT have the app layout (sidebars, header, etc.)
  const publicPages = ['/login', '/register']
  const isPublicPage = publicPages.includes(pathname)

  // Also check for upload page - it should have its own layout
  const isUploadPage = pathname === '/upload'

  if (isPublicPage || isUploadPage) {
    // Render public pages and upload page without app layout
    return <>{children}</>
  }

  // Render authenticated pages with full app layout
  return <AppLayout>{children}</AppLayout>
}
