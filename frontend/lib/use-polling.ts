/**
 * Custom hook for polling transcript status
 * Automatically polls every 3 seconds while status is "processing"
 */

import { useState, useEffect, useCallback, useRef } from 'react'
import { apiClient } from './api-client'
import { TranscriptStatus } from './types'

interface PollingResult {
  status: TranscriptStatus
  progress: number
  error?: string
  isPolling: boolean
}

export function useTranscriptPolling(
  transcriptId: string | null,
  enabled: boolean = true,
  interval: number = 3000 // 3 seconds
): PollingResult {
  const [status, setStatus] = useState<TranscriptStatus>('processing')
  const [progress, setProgress] = useState(0)
  const [error, setError] = useState<string | undefined>()
  const [isPolling, setIsPolling] = useState(false)
  const intervalRef = useRef<NodeJS.Timeout | null>(null)

  const fetchStatus = useCallback(async () => {
    if (!transcriptId) return

    try {
      const result = await apiClient.getTranscriptStatus(transcriptId)
      setStatus(result.status)
      setProgress(result.progress_percent)
      setError(result.error_message)

      // Stop polling if completed or failed
      if (result.status === 'completed' || result.status === 'failed') {
        setIsPolling(false)
        if (intervalRef.current) {
          clearInterval(intervalRef.current)
          intervalRef.current = null
        }
      }
    } catch (err) {
      console.error('Error fetching transcript status:', err)
      setError(err instanceof Error ? err.message : 'Unknown error')
      setIsPolling(false)
      if (intervalRef.current) {
        clearInterval(intervalRef.current)
        intervalRef.current = null
      }
    }
  }, [transcriptId])

  useEffect(() => {
    if (!transcriptId || !enabled) {
      setIsPolling(false)
      return
    }

    // Start polling
    setIsPolling(true)
    fetchStatus() // Fetch immediately

    intervalRef.current = setInterval(fetchStatus, interval)

    // Cleanup on unmount or when transcriptId changes
    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current)
        intervalRef.current = null
      }
      setIsPolling(false)
    }
  }, [transcriptId, enabled, interval, fetchStatus])

  return {
    status,
    progress,
    error,
    isPolling,
  }
}
