// API service configuration
// Prefer VITE_API_URL if set; otherwise use relative URLs (proxied by Vite/Nginx)
const getApiUrl = () => {
  const envUrl = import.meta?.env?.VITE_API_URL;
  if (envUrl && typeof envUrl === 'string' && envUrl.trim() !== '') {
    return envUrl.replace(/\/$/, '');
  }
  return '';
};

const API_BASE_URL = getApiUrl();

console.log('Frontend connecting to backend at:', API_BASE_URL);

export const api = {
  // Health check
  async health() {
    try {
      const response = await fetch(`${API_BASE_URL}/health`);
      return response.json();
    } catch (error) {
      console.error('Health check failed:', error);
      return { status: 'error', message: error.message };
    }
  },

  // File search endpoint
  async searchFiles(query, maxResults = 10) {
    try {
      const response = await fetch(`${API_BASE_URL}/api/search/files?query=${encodeURIComponent(query)}&max_results=${maxResults}`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
        },
      });
      return response.json();
    } catch (error) {
      console.error('File search failed:', error);
      return { success: false, error: error.message };
    }
  },

  // Chat session management
  async createChatSession(userId, title = 'New Chat') {
    try {
      const response = await fetch(`${API_BASE_URL}/api/chat/sessions`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          user_id: userId,
          title,
        }),
      });
      return response.json();
    } catch (error) {
      console.error('Create chat session failed:', error);
      return { success: false, error: error.message };
    }
  },

  async getChatSessions(userId) {
    try {
      // Note: This endpoint is not yet implemented in the API
      // For now, return empty sessions list
      console.warn('Get chat sessions endpoint not implemented, returning empty list');
      return { success: true, sessions: [] };
    } catch (error) {
      console.error('Get chat sessions failed:', error);
      return { success: false, error: error.message };
    }
  },

  async getChatHistory(sessionId) {
    try {
      const response = await fetch(`${API_BASE_URL}/api/chat/sessions/${sessionId}/history`);
      return response.json();
    } catch (error) {
      console.error('Get chat history failed:', error);
      return { success: false, error: error.message };
    }
  },

  // Chat message endpoint
  async sendChatMessage(sessionId, content, useRag = true, files = []) {
    try {
      const requestBody = {
        content: content,
        include_context: useRag
      };

      const response = await fetch(`${API_BASE_URL}/api/chat/${sessionId}/message`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(requestBody),
      });
      return response.json();
    } catch (error) {
      console.error('Send chat message failed:', error);
      return { success: false, error: error.message };
    }
  },

  // Legacy chat endpoint for backwards compatibility
  async chat(message, history = []) {
    console.warn('Using legacy chat endpoint, consider using sendChatMessage instead');
    try {
      // For backwards compatibility, we'll create a temporary session
      const sessionResponse = await this.createChatSession('legacy_user', 'Legacy Chat');
      if (sessionResponse.success) {
        return await this.sendChatMessage(sessionResponse.session_id, message, true, []);
      }
      return { success: false, error: 'Failed to create session' };
    } catch (error) {
      console.error('Legacy chat request failed:', error);
      return { success: false, error: error.message };
    }
  },

  // File upload - keeping for compatibility
  async uploadFile(file) {
    try {
      const formData = new FormData();
      formData.append('files', file);

      const response = await fetch(`${API_BASE_URL}/api/upload`, {
        method: 'POST',
        body: formData,
      });
      return response.json();
    } catch (error) {
      console.error('File upload failed:', error);
      return { success: false, error: error.message };
    }
  },

  // Transcription service health check
  async transcriptionHealth() {
    try {
      const response = await fetch(`${API_BASE_URL}/api/transcribe/health`);
      return response.json();
    } catch (error) {
      console.error('Transcription health check failed:', error);
      return { status: 'error', message: error.message };
    }
  },

  // Audio transcription using Whisper service
  async transcribeAudio(file) {
    try {
      const formData = new FormData();
      formData.append('file', file);

      const response = await fetch(`${API_BASE_URL}/api/transcribe`, {
        method: 'POST',
        body: formData,
      });

      if (!response.ok) {
        const errorData = await response.json();
        return { 
          success: false, 
          error: errorData.message || errorData.error || `HTTP ${response.status}` 
        };
      }

      const result = await response.json();
      
      // Check if the service returned an error response
      if (result.success === false) {
        return result; // Already has success: false and error message
      }

      // Return successful transcription
      return {
        success: true,
        text: result.text,
        language: result.language,
        duration: result.duration,
        segments: result.segments || [],
        message: result.message
      };

    } catch (error) {
      console.error('Transcription failed:', error);
      return { success: false, error: error.message || 'Network error during transcription' };
    }
  },

  // Document management - using file search for now
  async getDocuments() {
    try {
      // Use search with empty query to get all documents
      return await this.searchFiles('', 100);
    } catch (error) {
      console.error('Get documents failed:', error);
      return { success: false, error: error.message };
    }
  },

  // Delete document - placeholder
  async deleteDocument(docId) {
    try {
      console.warn('Document deletion not yet implemented in new API');
      return { success: false, error: 'Delete endpoint not available' };
    } catch (error) {
      console.error('Delete document failed:', error);
      return { success: false, error: error.message };
    }
  },
}; 
