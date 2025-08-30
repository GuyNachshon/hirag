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
      const response = await fetch(`${API_BASE_URL}/api/search`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          query,
          max_results: maxResults,
        }),
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
      const response = await fetch(`${API_BASE_URL}/api/chat/sessions?user_id=${userId}`);
      return response.json();
    } catch (error) {
      console.error('Get chat sessions failed:', error);
      return { success: false, error: error.message };
    }
  },

  async getChatHistory(sessionId) {
    try {
      const response = await fetch(`${API_BASE_URL}/api/chat/sessions/${sessionId}/messages`);
      return response.json();
    } catch (error) {
      console.error('Get chat history failed:', error);
      return { success: false, error: error.message };
    }
  },

  // Chat message endpoint
  async sendChatMessage(sessionId, content, useRag = true, files = []) {
    try {
      const formData = new FormData();
      formData.append('content', content);
      formData.append('use_rag', useRag);
      
      // Add files if any
      files.forEach(file => {
        formData.append('files', file);
      });

      const response = await fetch(`${API_BASE_URL}/api/chat/sessions/${sessionId}/messages`, {
        method: 'POST',
        body: formData,
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

  // Audio transcription - placeholder for future whisper integration
  async transcribeAudio(file) {
    try {
      // TODO: Implement whisper transcription endpoint when ready
      console.warn('Audio transcription not yet implemented in new API');
      return { success: false, error: 'Transcription endpoint not available' };
    } catch (error) {
      console.error('Transcription failed:', error);
      return { success: false, error: error.message };
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
