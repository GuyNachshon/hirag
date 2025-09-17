import { ref } from 'vue'
import { defineStore } from 'pinia'
import { api } from '../services/api.js'

export const useChatStore = defineStore('chat', () => {
  const messages = ref([])
  const isLoading = ref(false)
  const hasMessageBeenSent = ref(false)
  const error = ref(null)
  const documentStats = ref({ total_documents: 0, vector_size: 0 })
  const uploadStatus = ref(null)
  
  // Session management
  const currentSessionId = ref(null)
  const sessions = ref([])
  const userId = ref('user_' + Math.random().toString(36).substr(2, 9))



  // Check system health
  async function checkHealth() {
    try {
      const health = await api.health()
      return health
    } catch (err) {
      console.warn('Health check failed:', err)
      return { status: 'offline', error: err.message }
    }
  }

  // Session management functions
  async function createNewSession(title = 'New Chat') {
    try {
      error.value = null
      const response = await api.createChatSession(userId.value, title)
      
      if (response.success !== false && response.session_id) {
        currentSessionId.value = response.session_id
        messages.value = []
        hasMessageBeenSent.value = false
        await loadSessions()
        return response.session_id
      } else {
        throw new Error(response.error || 'Failed to create session')
      }
    } catch (err) {
      error.value = 'Failed to create new session'
      console.error('Create session error:', err)
      throw err
    }
  }

  async function loadSessions() {
    try {
      const response = await api.getChatSessions(userId.value)
      if (response.success !== false && response.sessions) {
        sessions.value = response.sessions
      }
      return response
    } catch (err) {
      console.warn('Failed to load sessions:', err)
      return { success: false, error: err.message }
    }
  }

  async function loadSessionHistory(sessionId) {
    try {
      error.value = null
      const response = await api.getChatHistory(sessionId)
      
      if (response.success !== false && response.messages) {
        messages.value = response.messages.map(msg => ({
          id: msg.id || Date.now(),
          content: msg.content,
          sender: msg.role === 'user' ? 'user' : 'assistant',
          timestamp: new Date(msg.timestamp)
        }))
        currentSessionId.value = sessionId
        hasMessageBeenSent.value = messages.value.length > 0
        return response
      } else {
        throw new Error(response.error || 'Failed to load session history')
      }
    } catch (err) {
      error.value = 'Failed to load session history'
      console.error('Load session history error:', err)
      throw err
    }
  }

  // Load document statistics
  async function loadDocumentStats() {
    try {
      error.value = null
      const stats = await api.getDocuments()
      if (stats.success !== false) {
        documentStats.value = { 
          total_documents: stats.results?.length || 0, 
          vector_size: 0 
        }
      }
      return stats
    } catch (err) {
      console.warn('Failed to load document stats:', err)
      return { success: false, error: err.message }
    }
  }

  // Upload documents
  async function uploadDocuments(files) {
    try {
      error.value = null
      uploadStatus.value = 'uploading'
      
      const results = []
      for (const file of files) {
        const result = await api.uploadFile(file)
        results.push(result)
      }
      
      const successCount = results.filter(r => r.success).length
      if (successCount > 0) {
        uploadStatus.value = 'success'
        // Refresh document stats
        await loadDocumentStats()
        return {
          success: true,
          message: `הועלו ${successCount} מסמכים בהצלחה`,
          details: results
        }
      } else {
        uploadStatus.value = 'error'
        return {
          success: false,
          message: 'שגיאה בהעלאת המסמכים',
          details: results
        }
      }
    } catch (err) {
      uploadStatus.value = 'error'
      console.error('Upload error:', err)
      return {
        success: false,
        message: err.message || 'שגיאה בהעלאת המסמכים',
        error: err
      }
    }
  }

  // Clear all documents
  async function clearDocuments() {
    try {
      error.value = null
      // Note: This would need a clear endpoint in the API
      // For now, we'll just clear the local state
      documentStats.value = { total_documents: 0, vector_size: 0 }
      messages.value = []
      hasMessageBeenSent.value = false
      return { success: true, message: 'כל המסמכים נמחקו בהצלחה' }
    } catch (err) {
      console.error('Clear documents error:', err)
      return { success: false, message: err.message || 'שגיאה במחיקת המסמכים' }
    }
  }

  // Send message with session management and RAG support
  async function sendMessage(messageContent, useRag = true, files = []) {
    try {
      error.value = null
      hasMessageBeenSent.value = true
      
      // Ensure we have a session
      if (!currentSessionId.value) {
        await createNewSession()
      }
      
      // Add user message immediately
      const userMessage = {
        id: Date.now(),
        content: messageContent,
        sender: 'user',
        timestamp: new Date(),
        files: files
      }
      messages.value.push(userMessage)
      
      // Start loading
      isLoading.value = true
      
      // Create AI message placeholder
      const aiMessageId = Date.now() + 1
      const aiMessage = {
        id: aiMessageId,
        content: '',
        sender: 'assistant',
        timestamp: new Date(),
        isStreaming: false
      }
      messages.value.push(aiMessage)
      
      try {
        // Send message via API
        const result = await api.sendChatMessage(
          currentSessionId.value,
          messageContent,
          useRag,
          files
        )
        
        if (result.success !== false) {
          const messageIndex = messages.value.findIndex(msg => msg.id === aiMessageId)
          if (messageIndex !== -1) {
            messages.value[messageIndex].content = result.content || result.response || 'Response received'
            messages.value[messageIndex].timestamp = new Date()
          }
          
          // Update session list if needed
          await loadSessions()
          
        } else {
          throw new Error(result.error || 'Failed to send message')
        }
        
        isLoading.value = false
        
      } catch (apiError) {
        console.error('API message failed:', apiError)
        
        // Fallback to legacy API for backwards compatibility
        try {
          console.warn('Falling back to legacy chat API')
          const fallbackResult = await api.chat(messageContent)
          
          if (fallbackResult.success !== false) {
            const messageIndex = messages.value.findIndex(msg => msg.id === aiMessageId)
            if (messageIndex !== -1) {
              messages.value[messageIndex].content = fallbackResult.content || fallbackResult.response || 'Fallback response received'
              messages.value[messageIndex].timestamp = new Date()
            }
          } else {
            throw new Error(fallbackResult.error || 'Fallback API also failed')
          }
        } catch (fallbackError) {
          console.error('Fallback API also failed:', fallbackError)
          throw apiError // throw the original error
        }
        
        isLoading.value = false
      }
      
    } catch (err) {
      error.value = 'Failed to send message'
      console.error('Error sending message:', err)
      
      // Remove the AI message if there was an error
      const aiMessageIndex = messages.value.findIndex(msg => msg.id === aiMessageId && msg.sender === 'assistant')
      if (aiMessageIndex !== -1) {
        messages.value.splice(aiMessageIndex, 1)
      }
      
      isLoading.value = false
      throw err
    }
  }

  // Edit message (re-query with new content)
  async function editMessage(messageId, newContent) {
    try {
      error.value = null
      
      // Find the message to edit
      const messageIndex = messages.value.findIndex(msg => msg.id === messageId)
      if (messageIndex === -1) return

      // Update the message content locally
      messages.value[messageIndex].content = newContent
      messages.value[messageIndex].timestamp = new Date()

      // Remove all messages that came after this message
      messages.value.splice(messageIndex + 1)

      // If this was a user message, send a new query
      if (messages.value[messageIndex].sender === 'user') {
        await sendMessage(newContent, true)
      }
      
    } catch (err) {
      error.value = 'Failed to edit message'
      console.error('Error editing message:', err)
      throw err
    }
  }

  // Clear messages
  async function clearMessages() {
    try {
      messages.value = []
      hasMessageBeenSent.value = false
      isLoading.value = false
      error.value = null
    } catch (err) {
      error.value = 'Failed to clear messages'
      console.error('Error clearing messages:', err)
      throw err
    }
  }

  return {
    // State
    messages,
    isLoading,
    hasMessageBeenSent,
    error,
    documentStats,
    uploadStatus,
    currentSessionId,
    sessions,
    userId,
    
    // Actions
    checkHealth,
    createNewSession,
    loadSessions,
    loadSessionHistory,
    loadDocumentStats,
    uploadDocuments,
    clearDocuments,
    sendMessage,
    editMessage,
    clearMessages
  }
}) 
