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
      const response = await fetch(`${API_BASE_URL}/api/v1/health`);
      return response.json();
    } catch (error) {
      console.error('Health check failed:', error);
      return { status: 'error', message: error.message };
    }
  },

  // Chat endpoints
  async chat(message, history = []) {
    try {
      const response = await fetch(`${API_BASE_URL}/api/v1/chat`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message,
          history,
        }),
      });
      return response.json();
    } catch (error) {
      console.error('Chat request failed:', error);
      return { success: false, error: error.message };
    }
  },

  // Streaming chat
  async chatStream(message, history = [], onChunk) {
    try {
      const controller = new AbortController();
      const response = await fetch(`${API_BASE_URL}/api/v1/chat/stream`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message,
          history,
        }),
        signal: controller.signal,
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      if (!response.body) {
        throw new Error('ReadableStream not supported by this browser');
      }

      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';
      const idleMs = 30000; // 30s idle timeout for stalled streams
      let idleTimer = setTimeout(() => controller.abort('Stream timeout: no data received'), idleMs);

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        // Reset idle timer on any data
        clearTimeout(idleTimer);
        idleTimer = setTimeout(() => controller.abort('Stream timeout: no data received'), idleMs);

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n');
        buffer = lines.pop() || '';

        for (let raw of lines) {
          const line = raw.trim();
          if (!line) continue;
          if (line.startsWith('data:')) {
            const data = line.replace(/^data:\s*/, '');
            if (data === '[DONE]') return;
            try {
              const parsed = JSON.parse(data);
              onChunk(parsed);
            } catch (e) {
              // If not valid JSON, ignore the line
              // console.debug('Skipping non-JSON SSE data line:', data)
            }
          }
        }
      }

      // Flush any remaining buffered line
      if (buffer.trim().startsWith('data:')) {
        const data = buffer.trim().replace(/^data:\s*/, '');
        if (data !== '[DONE]') {
          try {
            const parsed = JSON.parse(data);
            onChunk(parsed);
          } catch (_) {}
        }
      }

      clearTimeout(idleTimer);
    } catch (error) {
      console.error('Streaming chat failed:', error);
      throw error;
    }
  },

  // File upload
  async uploadFile(file) {
    try {
      const formData = new FormData();
      formData.append('file', file);

      const response = await fetch(`${API_BASE_URL}/api/v1/upload`, {
        method: 'POST',
        body: formData,
      });
      return response.json();
    } catch (error) {
      console.error('File upload failed:', error);
      return { success: false, error: error.message };
    }
  },

  // Transcription
  async transcribeAudio(file) {
    try {
      const formData = new FormData();
      formData.append('file', file);

      const response = await fetch(`${API_BASE_URL}/api/v1/transcribe`, {
        method: 'POST',
        body: formData,
      });
      return response.json();
    } catch (error) {
      console.error('Transcription failed:', error);
      return { success: false, error: error.message };
    }
  },

  // Get documents
  async getDocuments() {
    try {
      const response = await fetch(`${API_BASE_URL}/api/v1/documents`);
      return response.json();
    } catch (error) {
      console.error('Get documents failed:', error);
      return { success: false, error: error.message };
    }
  },

  // Delete document
  async deleteDocument(docId) {
    try {
      const response = await fetch(`${API_BASE_URL}/api/v1/documents/${docId}`, {
        method: 'DELETE',
      });
      return response.json();
    } catch (error) {
      console.error('Delete document failed:', error);
      return { success: false, error: error.message };
    }
  },
}; 
