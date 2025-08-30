# API Integration Setup & Architecture

This document describes the complete API integration architecture, data flow, and implementation details for the chat application.

## Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   UI Components │    │  Pinia Store    │    │  API Service    │    │   Backend API   │
│                 │    │                 │    │                 │    │                 │
│ • Chat.vue      │◄──►│ • useChatStore  │◄──►│ • ApiService    │◄──►│ • Node.js/Express│
│ • PromptBox.vue │    │ • State Mgmt    │    │ • HTTP Client   │    │ • Streaming     │
│ • ChatTurn.vue  │    │ • Actions       │    │ • File Upload   │    │ • File Storage  │
└─────────────────┘    └─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Data Flow

### 1. Message Sending Flow
```
User Input → PromptBox → Chat Store → API Service → Backend
                                    ↓
UI Update ← Chat Store ← Streaming Response ← Backend
```

### 2. File Upload Flow
```
File Selection → PromptBox → Chat Store → API Service → Backend
                                    ↓
File Preview ← Chat Store ← Upload Response ← Backend
```

### 3. Conversation Management Flow
```
URL Change → Router → Chat Component → Chat Store → API Service → Backend
                                    ↓
UI Update ← Chat Store ← Conversation Data ← Backend
```

## Data Structures

### Message Object
```javascript
{
  id: string,                    // Unique message ID
  content: string,               // Message text content
  sender: 'user' | 'assistant',  // Message author
  timestamp: Date,               // Message timestamp
  files: FileObject[],           // Attached files
  isStreaming?: boolean          // Streaming indicator
}
```

### File Object
```javascript
{
  id: string,                    // Unique file ID
  name: string,                  // Original filename
  size: number,                  // File size in bytes
  type: string,                  // MIME type
  url: string                    // File download URL
}
```

### Conversation Object
```javascript
{
  id: string,                    // Unique conversation ID
  title: string,                 // Conversation title
  lastMessage: string,           // Last message content
  timestamp: string              // Last activity timestamp
}
```

## API Endpoints & Implementation

### 1. Create Conversation
```javascript
// Frontend Request
POST /api/conversations
Content-Type: application/json

// Backend Response
{
  "conversationId": "conv_123456789"
}

// Implementation
async createConversation() {
  const response = await fetch(`${this.baseURL}/conversations`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' }
  })
  const data = await response.json()
  return data
}
```

### 2. Send Message (Streaming)
```javascript
// Frontend Request
POST /api/chat
Content-Type: multipart/form-data

Form Data:
- message: string
- files: File[] (optional)
- conversationId: string (optional)

// Backend Response (Server-Sent Events)
data: {"content": "Hello"}
data: {"content": " world"}
data: [DONE]

// Implementation
async sendMessage(message, files = [], onChunk, onComplete) {
  const formData = new FormData()
  formData.append('message', message)
  
  if (files.length > 0) {
    files.forEach(file => formData.append('files', file))
  }
  
  if (this.conversationId) {
    formData.append('conversationId', this.conversationId)
  }

  const response = await fetch(`${this.baseURL}/chat`, {
    method: 'POST',
    body: formData
  })

  // Handle streaming
  const reader = response.body.getReader()
  const decoder = new TextDecoder()
  let buffer = ''
  let fullResponse = ''

  while (true) {
    const { done, value } = await reader.read()
    if (done) break

    buffer += decoder.decode(value, { stream: true })
    const lines = buffer.split('\n')
    buffer = lines.pop()

    for (const line of lines) {
      if (line.startsWith('data: ')) {
        const data = line.slice(6)
        
        if (data === '[DONE]') {
          if (onComplete) onComplete(fullResponse)
          return fullResponse
        }

        try {
          const parsed = JSON.parse(data)
          if (parsed.content) {
            fullResponse += parsed.content
            if (onChunk) onChunk(parsed.content, fullResponse)
          }
        } catch (e) {
          // Skip invalid JSON
        }
      }
    }
  }
}
```

### 3. Load Conversation History
```javascript
// Frontend Request
GET /api/conversations/{conversationId}/messages

// Backend Response
{
  "messages": [
    {
      "id": "msg_123",
      "content": "Hello",
      "sender": "user",
      "timestamp": "2024-01-01T12:00:00Z",
      "files": []
    },
    {
      "id": "msg_124",
      "content": "Hi there! How can I help?",
      "sender": "assistant",
      "timestamp": "2024-01-01T12:00:01Z",
      "files": []
    }
  ]
}

// Implementation
async loadConversationHistory(conversationId) {
  const response = await fetch(`${this.baseURL}/conversations/${conversationId}/messages`)
  const data = await response.json()
  return data.messages || []
}
```

### 4. Upload File
```javascript
// Frontend Request
POST /api/upload
Content-Type: multipart/form-data

Form Data:
- file: File

// Backend Response
{
  "url": "https://example.com/files/document.pdf",
  "name": "document.pdf",
  "size": 1024000,
  "type": "application/pdf"
}

// Implementation
async uploadFile(file) {
  const formData = new FormData()
  formData.append('file', file)

  const response = await fetch(`${this.baseURL}/upload`, {
    method: 'POST',
    body: formData
  })

  const data = await response.json()
  return data
}
```

### 5. Edit Message
```javascript
// Frontend Request
PATCH /api/messages/{messageId}
Content-Type: application/json

{
  "content": "Updated message content"
}

// Backend Response
{
  "id": "msg_123",
  "content": "Updated message content",
  "timestamp": "2024-01-01T12:00:00Z"
}

// Implementation
async editMessage(messageId, newContent) {
  const response = await fetch(`${this.baseURL}/messages/${messageId}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ content: newContent })
  })
  
  const data = await response.json()
  return data
}
```

### 6. Get Conversations List
```javascript
// Frontend Request
GET /api/conversations

// Backend Response
{
  "conversations": [
    {
      "id": "conv_123",
      "title": "Conversation about AI",
      "lastMessage": "That's interesting!",
      "timestamp": "2024-01-01T12:00:00Z"
    }
  ]
}

// Implementation
async getConversations() {
  const response = await fetch(`${this.baseURL}/conversations`)
  const data = await response.json()
  return data.conversations || []
}
```

### 7. Delete Conversation
```javascript
// Frontend Request
DELETE /api/conversations/{conversationId}

// Backend Response
200 OK

// Implementation
async deleteConversation(conversationId) {
  const response = await fetch(`${this.baseURL}/conversations/${conversationId}`, {
    method: 'DELETE'
  })
  
  if (!response.ok) {
    throw new Error(`HTTP error! status: ${response.status}`)
  }
}
```

## State Management (Pinia Store)

### Store Structure
```javascript
// State
const messages = ref([])           // Current conversation messages
const isLoading = ref(false)       // Loading state
const hasMessageBeenSent = ref(false) // Whether conversation has started
const error = ref(null)            // Error state
const conversationId = ref(null)   // Current conversation ID
const conversations = ref([])      // List of all conversations

// Actions
- initializeConversation()         // Create new conversation
- loadConversationHistory(id)      // Load conversation messages
- sendMessage(content, files)      // Send message with streaming
- editMessage(id, content)         // Edit existing message
- uploadFile(file)                 // Upload single file
- switchConversation(id)           // Switch to different conversation
- deleteConversation(id)           // Delete conversation
- clearMessages()                  // Clear current conversation
```

### Message Sending with Streaming
```javascript
async function sendMessage(messageContent, files = []) {
  // 1. Add user message immediately
  const userMessage = {
    id: Date.now(),
    content: messageContent,
    sender: 'user',
    timestamp: new Date(),
    files: files
  }
  messages.value.push(userMessage)
  
  // 2. Create AI message placeholder for streaming
  const aiMessageId = Date.now() + 1
  const aiMessage = {
    id: aiMessageId,
    content: '',
    sender: 'assistant',
    timestamp: new Date(),
    isStreaming: true
  }
  messages.value.push(aiMessage)
  
  // 3. Send to API with streaming callbacks
  await apiService.sendMessage(
    messageContent,
    files,
    // onChunk callback - updates content as it streams
    (chunk, fullResponse) => {
      const messageIndex = messages.value.findIndex(msg => msg.id === aiMessageId)
      if (messageIndex !== -1) {
        messages.value[messageIndex].content = fullResponse
      }
    },
    // onComplete callback - finalizes message
    (fullResponse) => {
      const messageIndex = messages.value.findIndex(msg => msg.id === aiMessageId)
      if (messageIndex !== -1) {
        messages.value[messageIndex].content = fullResponse
        messages.value[messageIndex].isStreaming = false
        messages.value[messageIndex].timestamp = new Date()
      }
      isLoading.value = false
    }
  )
}
```

## URL Routing & Conversation Management

### Route Structure
```javascript
// Router configuration
{
  path: '/',
  name: 'home',
  redirect: '/chat'
},
{
  path: '/chat',
  name: 'chat',
  component: ChatView
},
{
  path: '/chat/:conversationId',
  name: 'conversation',
  component: ChatView,
  props: true
}
```

### Conversation Flow
1. **New Conversation**: `/` → User sends message → `/chat/{conversationId}`
2. **Existing Conversation**: `/chat/{conversationId}` → Load history
3. **Switch Conversation**: URL change → Load new conversation
4. **Error Handling**: Invalid ID → Redirect to `/`

### URL Management
```javascript
// In Chat.vue
const handleMessageSent = async (messageContent, files = []) => {
  // If first message and no conversation ID
  if (!route.params.conversationId && !chatStore.conversationId) {
    const conversationId = await chatStore.initializeConversation()
    router.push(`/chat/${conversationId}`)  // Update URL
  }
  await chatStore.sendMessage(messageContent, files)
}

// Watch for route changes
watch(() => route.params.conversationId, async (newConversationId) => {
  if (newConversationId && newConversationId !== chatStore.conversationId) {
    await chatStore.switchConversation(newConversationId)
  }
}, { immediate: true })
```

## Error Handling & Fallbacks

### API Error Handling
```javascript
// In API Service
try {
  const response = await fetch(url, options)
  if (!response.ok) {
    throw new Error(`HTTP error! status: ${response.status}`)
  }
  return await response.json()
} catch (error) {
  console.error('API Error:', error)
  throw error
}
```

### Mock Fallback System
```javascript
// In Chat Store
try {
  await apiService.sendMessage(messageContent, files, onChunk, onComplete)
} catch (apiError) {
  console.warn('API failed, using mock response:', apiError)
  
  // Fallback to mock response with simulated streaming
  const mockResponse = mockResponses[Math.floor(Math.random() * mockResponses.length)]
  const words = mockResponse.split(' ')
  let currentResponse = ''
  
  // Simulate streaming
  for (let i = 0; i < words.length; i++) {
    await new Promise(resolve => setTimeout(resolve, 100 + Math.random() * 200))
    currentResponse += (i > 0 ? ' ' : '') + words[i]
    
    const messageIndex = messages.value.findIndex(msg => msg.id === aiMessageId)
    if (messageIndex !== -1) {
      messages.value[messageIndex].content = currentResponse
    }
  }
  
  // Complete mock response
  const messageIndex = messages.value.findIndex(msg => msg.id === aiMessageId)
  if (messageIndex !== -1) {
    messages.value[messageIndex].isStreaming = false
    messages.value[messageIndex].timestamp = new Date()
  }
  isLoading.value = false
}
```

## File Upload Implementation

### Frontend File Handling
```javascript
// In PromptBox.vue
const handleFileSelect = (event) => {
  const files = Array.from(event.target.files)
  
  // Validate files
  const validFiles = files.filter(file => {
    const isValidType = allowedTypes.includes(file.type)
    const isValidSize = file.size <= maxFileSize
    return isValidType && isValidSize
  })
  
  // Add to selected files
  selectedFiles.value.push(...validFiles)
}

// File validation
const allowedTypes = [
  'image/jpeg', 'image/png', 'image/gif', 'image/webp',
  'application/pdf', 'text/plain',
  'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
]
const maxFileSize = 10 * 1024 * 1024 // 10MB
```

### File Upload Process
```javascript
// 1. User selects files in PromptBox
// 2. Files are validated and previewed
// 3. When sending message:
const handleMessageSent = async (messageContent, files = []) => {
  // Files are already validated and ready
  await chatStore.sendMessage(messageContent, files)
}

// 4. In store, files are sent with message
const formData = new FormData()
formData.append('message', messageContent)
files.forEach(file => formData.append('files', file))
```

## Environment Configuration

### Frontend Environment Variables
```env
# .env
VITE_API_BASE_URL=http://localhost:3000/api
VITE_API_KEY=your_api_key_here  # Optional
```

### Backend Environment Variables
```env
# Backend .env
PORT=3000
DATABASE_URL=your_database_url
FILE_STORAGE_PATH=./uploads
MAX_FILE_SIZE=10485760  # 10MB
ALLOWED_FILE_TYPES=image/jpeg,image/png,application/pdf
```

## Development Setup

### Frontend Development
```bash
# Install dependencies
npm install

# Start development server
npm run dev

# Build for production
npm run build
```

### Backend Development Requirements
```javascript
// Required Node.js packages
{
  "express": "^4.18.0",
  "multer": "^1.4.5",           // File upload handling
  "cors": "^2.8.5",            // Cross-origin requests
  "helmet": "^7.0.0",          // Security headers
  "express-rate-limit": "^6.0.0" // Rate limiting
}
```

### Backend Server Setup
```javascript
// Basic Express server structure
const express = require('express')
const multer = require('multer')
const cors = require('cors')

const app = express()

app.use(cors())
app.use(express.json())

// File upload configuration
const upload = multer({
  dest: 'uploads/',
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB
  fileFilter: (req, file, cb) => {
    // Validate file types
    const allowedTypes = ['image/jpeg', 'image/png', 'application/pdf']
    if (allowedTypes.includes(file.mimetype)) {
      cb(null, true)
    } else {
      cb(new Error('Invalid file type'))
    }
  }
})

// Routes
app.post('/api/conversations', createConversation)
app.get('/api/conversations/:id/messages', getConversationHistory)
app.post('/api/chat', upload.array('files'), sendMessage)
app.post('/api/upload', upload.single('file'), uploadFile)
app.delete('/api/conversations/:id', deleteConversation)
app.patch('/api/messages/:id', editMessage)
```

## Testing & Debugging

### Frontend Testing
```javascript
// Test API service
const apiService = new ApiService()
const conversation = await apiService.createConversation()
console.log('Created conversation:', conversation)

// Test message sending
await apiService.sendMessage('Hello', [], 
  (chunk) => console.log('Chunk:', chunk),
  (complete) => console.log('Complete:', complete)
)
```

### Backend Testing
```bash
# Test endpoints with curl
curl -X POST http://localhost:3000/api/conversations
curl -X POST http://localhost:3000/api/chat \
  -F "message=Hello" \
  -F "conversationId=conv_123"
```

### Debugging Tips
1. **Check Network Tab**: Monitor API requests and responses
2. **Console Logs**: Frontend logs API errors and fallbacks
3. **Streaming Debug**: Check SSE data format in Network tab
4. **File Upload**: Verify FormData structure and file validation
5. **CORS Issues**: Ensure backend allows frontend origin

## Security Considerations

### Frontend Security
- File type validation on client and server
- File size limits enforced
- Input sanitization for messages
- HTTPS in production

### Backend Security
- Rate limiting on API endpoints
- File upload validation and sanitization
- CORS configuration
- Input validation and sanitization
- Authentication/authorization (if needed)

## Performance Optimization

### Frontend Optimizations
- Debounced message sending
- Virtual scrolling for long conversations
- Image lazy loading
- File compression before upload

### Backend Optimizations
- Streaming responses for real-time updates
- File compression and optimization
- Database indexing for conversation queries
- Caching for frequently accessed data 