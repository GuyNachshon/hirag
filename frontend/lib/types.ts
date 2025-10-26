/**
 * TypeScript types matching the API models
 * These interfaces define the data structures used throughout the frontend
 */

// ===================================
// Authentication Types
// ===================================

export interface User {
  user_id: string
  username: string
  created_at: string
}

export interface AuthResponse {
  user_id: string
  username: string
  token: string
  expires_at: string
}

export interface LoginRequest {
  username: string
  password: string
}

export interface RegisterRequest {
  username: string
  password: string
}

// ===================================
// Folder Types
// ===================================

export interface Folder {
  id: string
  name: string
  transcript_count: number
  created_at: string
  updated_at: string
}

export interface FolderCreateRequest {
  name: string
}

export interface FolderUpdateRequest {
  name: string
}

// ===================================
// Transcript Types
// ===================================

export type TranscriptStatus = "processing" | "completed" | "failed"

export interface TranscriptSegment {
  start: number
  end: number
  text: string
  speaker?: string
}

export interface TranscriptListItem {
  id: string
  title: string
  duration?: number
  status: TranscriptStatus
  folder_id?: string
  folder_name?: string
  tags: string[]
  speakers: string[]
  language: string
  created_at: string
  updated_at: string
  completed_at?: string
}

export interface TranscriptDetail {
  id: string
  title: string
  duration?: number
  status: TranscriptStatus
  folder_id?: string
  folder_name?: string
  tags: string[]
  language: string
  full_text?: string
  language_probability?: number
  diarization_enabled: boolean
  num_speakers?: number
  speaker_names?: Record<string, string>
  segments: TranscriptSegment[]
  created_at: string
  updated_at: string
  completed_at?: string
}

// Alias for backward compatibility
export type TranscriptDetailResponse = TranscriptDetail

export interface TranscriptUploadResponse {
  transcript_id: string
  status: TranscriptStatus
  message: string
}

export interface TranscriptStatusResponse {
  transcript_id: string
  status: TranscriptStatus
  progress_percent: number
  error_message?: string
}

export interface TranscriptUpdateRequest {
  title?: string
  folder_id?: string
  tags?: string[]
}

export type ExportFormat = "txt" | "json" | "pdf"

// ===================================
// API Response Types
// ===================================

export interface TranscriptListResponse {
  transcripts: TranscriptListItem[]
  total_count: number
}

export interface FolderListResponse {
  folders: Folder[]
  total_count: number
}

// ===================================
// Upload Flow Types
// ===================================

export type UploadStep = "select" | "uploading" | "processing" | "complete"

export interface UploadState {
  step: UploadStep
  file: File | null
  title: string
  folder: string
  tags: string
  uploadProgress: number
  transcriptId?: string
  error?: string
}

// ===================================
// Chat Types (for AI chat sidebar)
// ===================================

export interface ChatMessage {
  id: string
  role: "user" | "assistant"
  content: string
  timestamp: Date
}

// ===================================
// API Error Types
// ===================================

export interface APIError {
  detail: string
  status?: number
}

// ===================================
// Search Types
// ===================================

export interface SearchFilters {
  q?: string
  folder_id?: string
  tags?: string[]
  date_from?: Date
  date_to?: Date
  limit?: number
  offset?: number
}

// ===================================
// Quick Actions Types
// ===================================

export interface QuickAction {
  id: string
  label: string
  icon: string
  prompt_template: string
  description?: string
}

export interface QuickActionsResponse {
  context: "folder" | "transcript"
  actions: QuickAction[]
}

export type QuickActionContext = "folder" | "transcript"
