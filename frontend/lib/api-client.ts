/**
 * API client for communicating with the backend
 * Handles authentication, error handling, and all API calls
 */

import {
  AuthResponse,
  LoginRequest,
  RegisterRequest,
  User,
  Folder,
  FolderCreateRequest,
  FolderUpdateRequest,
  FolderListResponse,
  TranscriptListItem,
  TranscriptListResponse,
  TranscriptDetail,
  TranscriptUploadResponse,
  TranscriptStatusResponse,
  TranscriptUpdateRequest,
  ExportFormat,
  SearchFilters,
  APIError,
  QuickActionsResponse,
  QuickActionContext,
} from './types'
import { getStoredToken, clearStoredToken } from './auth'

class APIClient {
  private baseURL: string

  constructor() {
    this.baseURL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8080'
  }

  /**
   * Make an authenticated API request
   */
  private async request<T>(
    endpoint: string,
    options: RequestInit = {}
  ): Promise<T> {
    const token = getStoredToken()
    const headers: HeadersInit = {
      ...options.headers,
    }

    // Add auth token if available
    if (token) {
      headers['Authorization'] = `Bearer ${token}`
    }

    // Add Content-Type for JSON requests
    if (options.body && typeof options.body === 'string') {
      headers['Content-Type'] = 'application/json'
    }

    const response = await fetch(`${this.baseURL}${endpoint}`, {
      ...options,
      headers,
    })

    // Handle 401 Unauthorized - token expired or invalid
    if (response.status === 401) {
      clearStoredToken()
      if (typeof window !== 'undefined') {
        window.location.href = '/login'
      }
      throw new Error('Unauthorized - please log in again')
    }

    // Handle other errors
    if (!response.ok) {
      let errorMessage = `HTTP ${response.status}: ${response.statusText}`

      try {
        const errorData: APIError = await response.json()
        errorMessage = errorData.detail || errorMessage
      } catch (e) {
        // If error parsing fails, use default message
      }

      throw new Error(errorMessage)
    }

    // Return empty object for 204 No Content
    if (response.status === 204) {
      return {} as T
    }

    return response.json()
  }

  // ===================================
  // Authentication Methods
  // ===================================

  async register(username: string, password: string): Promise<AuthResponse> {
    return this.request<AuthResponse>('/api/auth/register', {
      method: 'POST',
      body: JSON.stringify({ username, password }),
    })
  }

  async login(username: string, password: string): Promise<AuthResponse> {
    return this.request<AuthResponse>('/api/auth/login', {
      method: 'POST',
      body: JSON.stringify({ username, password }),
    })
  }

  async logout(): Promise<void> {
    await this.request('/api/auth/logout', { method: 'POST' })
  }

  async getCurrentUser(): Promise<User> {
    return this.request<User>('/api/auth/me')
  }

  async changePassword(
    currentPassword: string,
    newPassword: string
  ): Promise<void> {
    await this.request('/api/auth/change-password', {
      method: 'POST',
      body: JSON.stringify({
        current_password: currentPassword,
        new_password: newPassword,
      }),
    })
  }

  // ===================================
  // Folder Methods
  // ===================================

  async listFolders(): Promise<FolderListResponse> {
    return this.request<FolderListResponse>('/api/folders')
  }

  async createFolder(name: string): Promise<Folder> {
    return this.request<Folder>('/api/folders', {
      method: 'POST',
      body: JSON.stringify({ name }),
    })
  }

  async getFolder(folderId: string): Promise<Folder> {
    return this.request<Folder>(`/api/folders/${folderId}`)
  }

  async updateFolder(folderId: string, name: string): Promise<Folder> {
    return this.request<Folder>(`/api/folders/${folderId}`, {
      method: 'PATCH',
      body: JSON.stringify({ name }),
    })
  }

  async deleteFolder(
    folderId: string,
    moveTo?: string
  ): Promise<{ message: string; transcripts_affected: number }> {
    const params = moveTo ? `?move_to=${moveTo}` : ''
    return this.request(`/api/folders/${folderId}${params}`, {
      method: 'DELETE',
    })
  }

  // ===================================
  // Transcript Methods
  // ===================================

  async uploadTranscript(
    file: File,
    title: string,
    options?: {
      folderId?: string
      tags?: string
      enableDiarization?: boolean
      identifySpeakers?: boolean
      numSpeakers?: number
      language?: string
    }
  ): Promise<TranscriptUploadResponse> {
    const formData = new FormData()
    formData.append('file', file)
    formData.append('title', title)

    if (options?.folderId) {
      formData.append('folder_id', options.folderId)
    }
    if (options?.tags) {
      formData.append('tags', options.tags)
    }
    formData.append(
      'enable_diarization',
      String(options?.enableDiarization ?? true)
    )
    formData.append(
      'identify_speakers',
      String(options?.identifySpeakers ?? false)
    )
    if (options?.numSpeakers !== undefined) {
      formData.append('num_speakers', String(options.numSpeakers))
    }
    formData.append('language', options?.language ?? 'he')

    const token = getStoredToken()
    const response = await fetch(`${this.baseURL}/api/transcription/upload`, {
      method: 'POST',
      headers: {
        ...(token && { Authorization: `Bearer ${token}` }),
      },
      body: formData,
    })

    if (!response.ok) {
      const error = await response.json()
      throw new Error(error.detail || 'Upload failed')
    }

    return response.json()
  }

  async getTranscriptStatus(
    transcriptId: string
  ): Promise<TranscriptStatusResponse> {
    return this.request<TranscriptStatusResponse>(
      `/api/transcription/status/${transcriptId}`
    )
  }

  async listTranscripts(params?: {
    folderId?: string
    status?: string
    limit?: number
    offset?: number
    sortBy?: string
    order?: 'asc' | 'desc'
  }): Promise<TranscriptListResponse> {
    const searchParams = new URLSearchParams()

    if (params?.folderId) searchParams.append('folder_id', params.folderId)
    if (params?.status) searchParams.append('status', params.status)
    if (params?.limit) searchParams.append('limit', String(params.limit))
    if (params?.offset) searchParams.append('offset', String(params.offset))
    if (params?.sortBy) searchParams.append('sort_by', params.sortBy)
    if (params?.order) searchParams.append('order', params.order)

    const queryString = searchParams.toString()
    const endpoint = `/api/transcription/list${queryString ? `?${queryString}` : ''}`

    return this.request<TranscriptListResponse>(endpoint)
  }

  async getTranscript(transcriptId: string): Promise<TranscriptDetail> {
    return this.request<TranscriptDetail>(
      `/api/transcription/${transcriptId}`
    )
  }

  async updateTranscript(
    transcriptId: string,
    updates: TranscriptUpdateRequest
  ): Promise<TranscriptDetail> {
    return this.request<TranscriptDetail>(
      `/api/transcription/${transcriptId}`,
      {
        method: 'PATCH',
        body: JSON.stringify(updates),
      }
    )
  }

  async deleteTranscript(
    transcriptId: string
  ): Promise<{ message: string }> {
    return this.request(`/api/transcription/${transcriptId}`, {
      method: 'DELETE',
    })
  }

  async generateInsights(transcriptId: string): Promise<{
    summary: string
    key_points: string[]
    action_items: string[]
    topics: string[]
  }> {
    return this.request(`/api/transcription/${transcriptId}/insights`, {
      method: 'POST',
    })
  }

  async exportTranscript(
    transcriptId: string,
    format: ExportFormat = 'txt'
  ): Promise<Blob> {
    const token = getStoredToken()
    const response = await fetch(
      `${this.baseURL}/api/transcription/${transcriptId}/export?format=${format}`,
      {
        headers: {
          ...(token && { Authorization: `Bearer ${token}` }),
        },
      }
    )

    if (!response.ok) {
      throw new Error('Export failed')
    }

    return response.blob()
  }

  // ===================================
  // Search Methods
  // ===================================

  async searchTranscripts(
    query: string,
    filters?: SearchFilters
  ): Promise<TranscriptListResponse> {
    const params = new URLSearchParams({ q: query })

    if (filters?.folder_id) params.append('folder_id', filters.folder_id)
    if (filters?.tags) params.append('tags', filters.tags.join(','))
    if (filters?.date_from)
      params.append('date_from', filters.date_from.toISOString())
    if (filters?.date_to)
      params.append('date_to', filters.date_to.toISOString())
    if (filters?.limit) params.append('limit', String(filters.limit))
    if (filters?.offset) params.append('offset', String(filters.offset))

    return this.request<TranscriptListResponse>(
      `/api/search/transcripts?${params.toString()}`
    )
  }

  async searchSpeakers(query: string): Promise<{ speakers: string[] }> {
    return this.request(`/api/search/speakers?q=${encodeURIComponent(query)}`)
  }

  // ===================================
  // Quick Actions Methods
  // ===================================

  async getQuickActions(context: QuickActionContext): Promise<QuickActionsResponse> {
    return this.request<QuickActionsResponse>(
      `/api/chat/quick-actions?context=${context}`
    )
  }

  // ===================================
  // Transcription Chat Methods
  // ===================================

  async createTranscriptionChatSession(
    contextType: 'folder' | 'transcript',
    contextId: string,
    name?: string
  ): Promise<{ session_id: string; context_type: string; context_id: string; created_at: string }> {
    return this.request(`/api/transcription/chat/sessions`, {
      method: 'POST',
      body: JSON.stringify({
        context_type: contextType,
        context_id: contextId,
        name,
      }),
    })
  }

  async sendTranscriptionChatMessage(
    sessionId: string,
    content: string,
    contextType: 'folder' | 'transcript',
    contextId: string,
    quickActionId?: string
  ): Promise<{
    message_id: string
    content: string
    timestamp: string
    strategy_used: string
    sources: string[]
    segment_references?: Array<{
      transcript_id: string
      transcript_title: string
      segment_id: string
      speaker: string | null
      start_time: number
      end_time: number
      text: string
    }>
    processing_time: number
  }> {
    return this.request(`/api/transcription/chat/${sessionId}/message`, {
      method: 'POST',
      body: JSON.stringify({
        content,
        context_type: contextType,
        context_id: contextId,
        quick_action_id: quickActionId,
        include_sources: true,
      }),
    })
  }

  async getTranscriptionChatHistory(sessionId: string): Promise<{
    session_id: string
    messages: Array<{
      message_id: string
      role: string
      content: string
      timestamp: string
      strategy_used?: string
      sources?: string[]
    }>
    total_messages: number
  }> {
    return this.request(`/api/transcription/chat/${sessionId}/history`)
  }

  async deleteTranscriptionChatSession(sessionId: string): Promise<{ message: string }> {
    return this.request(`/api/transcription/chat/${sessionId}`, {
      method: 'DELETE',
    })
  }
}

// Export singleton instance
export const apiClient = new APIClient()
