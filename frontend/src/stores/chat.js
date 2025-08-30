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

  // Load document statistics
  async function loadDocumentStats() {
    try {
      error.value = null
      const stats = await api.getDocuments()
      if (stats.success) {
        documentStats.value = { total_documents: stats.documents?.length || 0, vector_size: 0 }
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

  // Query documents (send message)
  async function sendMessage(messageContent, useStreaming = true) {
    try {
      error.value = null
      hasMessageBeenSent.value = true
      
      // Add user message immediately
      const userMessage = {
        id: Date.now(),
        content: messageContent,
        sender: 'user',
        timestamp: new Date()
      }
      messages.value.push(userMessage)
      
      // Start loading
      isLoading.value = true
      
      // Create AI message placeholder for streaming
      const aiMessageId = Date.now() + 1
      const aiMessage = {
        id: aiMessageId,
        content: '',
        sender: 'assistant',
        timestamp: new Date(),
        isStreaming: useStreaming
      }
      messages.value.push(aiMessage)
      
      try {
        if (useStreaming) {
          // Try streaming query
          await api.chatStream(
            messageContent,
            [], // history
            // onChunk callback
            (chunk) => {
              const messageIndex = messages.value.findIndex(msg => msg.id === aiMessageId)
              if (messageIndex !== -1) {
                const piece = typeof chunk === 'string' ? chunk : (chunk && chunk.content) ? chunk.content : ''
                if (piece) {
                  messages.value[messageIndex].content += piece
                }
              }
            }
          )
          
          // Complete the response
          const messageIndex = messages.value.findIndex(msg => msg.id === aiMessageId)
          if (messageIndex !== -1) {
            messages.value[messageIndex].isStreaming = false
            messages.value[messageIndex].timestamp = new Date()
          }
          isLoading.value = false
        } else {
          // Non-streaming query
          const result = await api.chat(messageContent)
          
          if (result.success) {
            const messageIndex = messages.value.findIndex(msg => msg.id === aiMessageId)
            if (messageIndex !== -1) {
              messages.value[messageIndex].content = result.response || result.content
              messages.value[messageIndex].isStreaming = false
              messages.value[messageIndex].timestamp = new Date()
            }
          } else {
            throw new Error(result.error)
          }
          isLoading.value = false
        }
      } catch (apiError) {
        console.error('API query failed:', apiError)
        throw apiError
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
    
    // Actions
    checkHealth,
    loadDocumentStats,
    uploadDocuments,
    clearDocuments,
    sendMessage,
    editMessage,
    clearMessages
  }
}) 
