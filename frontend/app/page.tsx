"use client"

import { LibraryView } from "@/components/library-view"
import { ProtectedRoute } from "@/lib/protected-route"

export default function HomePage() {
  return (
    <ProtectedRoute>
      <LibraryView />
    </ProtectedRoute>
  )
}
