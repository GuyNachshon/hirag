"use client"

import { createContext, useContext } from "react"
import type { Folder } from "./types"

interface UploadContextType {
  onOpenUpload: (file?: File) => void
  selectedFolder: string | null
  folders: Folder[]
}

const UploadContext = createContext<UploadContextType | null>(null)

export function useUpload() {
  const context = useContext(UploadContext)
  if (!context) {
    throw new Error("useUpload must be used within UploadProvider")
  }
  return context
}

export const UploadProvider = UploadContext.Provider
