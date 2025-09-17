<script setup>
import { ref, onMounted } from 'vue'
import { api } from '../services/api.js'

const audioFile = ref(null)
const transcription = ref('')
const isTranscribing = ref(false)
const transcriptionStatus = ref(null)
const error = ref(null)

const handleFileChange = (event) => {
  const file = event.target.files[0]
  if (file) {
    // Validate file type
    const allowedTypes = [
      'audio/wav', 'audio/mp3', 'audio/mpeg', 'audio/ogg', 
      'audio/flac', 'audio/aac', 'audio/webm', 'audio/m4a'
    ]
    
    if (!allowedTypes.includes(file.type)) {
      error.value = 'סוג קובץ לא נתמך. אנא העלה קובץ אודיו'
      return
    }
    
    // Check file size (max 100MB)
    if (file.size > 100 * 1024 * 1024) {
      error.value = 'קובץ גדול מדי. הגודל המקסימלי הוא 100MB'
      return
    }
    
    audioFile.value = file
    error.value = null
  }
}

const transcribeAudio = async () => {
  if (!audioFile.value) {
    error.value = 'אנא בחר קובץ אודיו'
    return
  }
  
  try {
    isTranscribing.value = true
    error.value = null
    transcription.value = ''
    
    const result = await api.transcribeAudio(audioFile.value)
    
    if (result.success) {
      transcription.value = result.text
    } else {
      error.value = result.error || 'תמלול נכשל'
    }
  } catch (err) {
    error.value = err.message || 'שגיאה בתמלול'
  } finally {
    isTranscribing.value = false
  }
}

const clearTranscription = () => {
  transcription.value = ''
  audioFile.value = null
  error.value = null
  // Reset file input
  const fileInput = document.getElementById('audio-file-input')
  if (fileInput) {
    fileInput.value = ''
  }
}

const copyTranscription = async () => {
  if (transcription.value) {
    try {
      await navigator.clipboard.writeText(transcription.value)
      // You could show a toast notification here
    } catch (err) {
      console.error('Failed to copy transcription:', err)
    }
  }
}

onMounted(async () => {
  try {
    // Check if transcription service is available via health check
    const health = await api.health()
    transcriptionStatus.value = {
      status: health.status === 'ok' ? 'active' : 'inactive',
      model: 'whisper' // Default model
    }
  } catch (err) {
    console.error('Failed to get transcription status:', err)
    transcriptionStatus.value = {
      status: 'inactive',
      model: 'unknown'
    }
  }
})
</script>

<template>
  <div class="transcription-wrapper">
    <div class="transcription">
      <div class="transcription__header">
        <h1>תמלול אודיו</h1>
        <p>העלה קובץ אודיו ותקבל תמלול בעברית</p>
      </div>
      
      <!-- Service Status -->
      <div v-if="transcriptionStatus" class="transcription__status">
        <div class="transcription__status__item">
          <span class="transcription__status__label">סטטוס שירות:</span>
          <span 
            class="transcription__status__value"
            :class="{ 'active': transcriptionStatus.status === 'active' }"
          >
            {{ transcriptionStatus.status === 'active' ? 'פעיל' : 'לא פעיל' }}
          </span>
        </div>
        <div class="transcription__status__item">
          <span class="transcription__status__label">מודל:</span>
          <span class="transcription__status__value">{{ transcriptionStatus.model }}</span>
        </div>
      </div>
      
      <!-- Error Display -->
      <div v-if="error" class="transcription__error">
        {{ error }}
      </div>
      
      <!-- File Upload -->
      <div class="transcription__upload">
        <div class="transcription__upload__area">
          <input
            id="audio-file-input"
            type="file"
            accept="audio/*"
            @change="handleFileChange"
            class="transcription__upload__input"
          />
          <div class="transcription__upload__content">
            <div class="transcription__upload__icon">
              <svg width="48" height="48" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M12 2C13.1 2 14 2.9 14 4V12C14 13.1 13.1 14 12 14C10.9 14 10 13.1 10 12V4C10 2.9 10.9 2 12 2Z" fill="currentColor"/>
                <path d="M19 10V12C19 15.87 15.87 19 12 19C8.13 19 5 15.87 5 12V10C5 9.45 5.45 9 6 9C6.55 9 7 9.45 7 10V12C7 14.76 9.24 17 12 17C14.76 17 17 14.76 17 12V10C17 9.45 17.45 9 18 9C18.55 9 19 9.45 19 10Z" fill="currentColor"/>
              </svg>
            </div>
            <div class="transcription__upload__text">
              <p v-if="!audioFile">לחץ לבחירת קובץ אודיו או גרור לכאן</p>
              <p v-else class="transcription__upload__filename">{{ audioFile.name }}</p>
            </div>
          </div>
        </div>
        
        <button
          @click="transcribeAudio"
          :disabled="!audioFile || isTranscribing"
          class="transcription__upload__button"
        >
          <span v-if="isTranscribing">מתמלל...</span>
          <span v-else>תמלל אודיו</span>
        </button>
      </div>
      
      <!-- Transcription Result -->
      <div v-if="transcription" class="transcription__result">
        <div class="transcription__result__header">
          <h3>תמלול</h3>
          <div class="transcription__result__actions">
            <button @click="copyTranscription" class="transcription__result__action">
              העתק
            </button>
            <button @click="clearTranscription" class="transcription__result__action">
              נקה
            </button>
          </div>
        </div>
        <div class="transcription__result__content">
          {{ transcription }}
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped lang="scss">
@import '../assets/variables.scss';

.transcription-wrapper {
  display: flex;
  height: 100vh;
  width: 100%;
  flex-direction: column;
  align-items: center;
  justify-content: flex-start;
  padding: calc($spacing * 4);
  box-sizing: border-box;
  direction: rtl;
}

.transcription {
  width: 100%;
  max-width: 800px;
  
  &__header {
    text-align: center;
    margin-bottom: calc($spacing * 6);
    
    h1 {
      font-size: 2.5rem;
      font-weight: 700;
      margin-bottom: calc($spacing * 2);
      color: $text-primary;
    }
    
    p {
      font-size: 1.1rem;
      color: $text-secondary;
    }
  }
  
  &__status {
    background: $background-secondary;
    border-radius: $border-radius;
    padding: calc($spacing * 3);
    margin-bottom: calc($spacing * 4);
    
    &__item {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: calc($spacing * 1);
      
      &:last-child {
        margin-bottom: 0;
      }
    }
    
    &__label {
      font-weight: 500;
      color: $text-secondary;
    }
    
    &__value {
      font-weight: 600;
      color: $text-primary;
      
      &.active {
        color: $success;
      }
    }
  }
  
  &__error {
    background: $error-light;
    color: $error;
    padding: calc($spacing * 3);
    border-radius: $border-radius;
    margin-bottom: calc($spacing * 4);
    text-align: center;
  }
  
  &__upload {
    margin-bottom: calc($spacing * 6);
    
    &__area {
      position: relative;
      border: 2px dashed $border-color;
      border-radius: $border-radius;
      padding: calc($spacing * 6);
      text-align: center;
      margin-bottom: calc($spacing * 4);
      transition: all 0.3s ease;
      
      &:hover {
        border-color: $primary;
        background: $background-secondary;
      }
    }
    
    &__input {
      position: absolute;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      opacity: 0;
      cursor: pointer;
    }
    
    &__content {
      pointer-events: none;
    }
    
    &__icon {
      color: $text-secondary;
      margin-bottom: calc($spacing * 2);
    }
    
    &__text {
      p {
        font-size: 1.1rem;
        color: $text-secondary;
        margin: 0;
      }
    }
    
    &__filename {
      color: $primary !important;
      font-weight: 600;
    }
    
    &__button {
      width: 100%;
      background: $primary;
      color: white;
      border: none;
      padding: calc($spacing * 3);
      border-radius: $border-radius;
      font-size: 1.1rem;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.3s ease;
      
      &:hover:not(:disabled) {
        background: $primary-dark;
      }
      
      &:disabled {
        background: $disabled;
        cursor: not-allowed;
      }
    }
  }
  
  &__result {
    background: $background-secondary;
    border-radius: $border-radius;
    padding: calc($spacing * 4);
    
    &__header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: calc($spacing * 3);
      
      h3 {
        font-size: 1.3rem;
        font-weight: 600;
        color: $text-primary;
        margin: 0;
      }
    }
    
    &__actions {
      display: flex;
      gap: calc($spacing * 2);
    }
    
    &__action {
      background: $background-primary;
      color: $text-primary;
      border: 1px solid $border-color;
      padding: calc($spacing * 1.5) calc($spacing * 3);
      border-radius: $border-radius;
      font-size: 0.9rem;
      cursor: pointer;
      transition: all 0.3s ease;
      
      &:hover {
        background: $primary;
        color: white;
        border-color: $primary;
      }
    }
    
    &__content {
      background: $background-primary;
      border: 1px solid $border-color;
      border-radius: $border-radius;
      padding: calc($spacing * 3);
      min-height: 120px;
      line-height: 1.6;
      color: $text-primary;
      white-space: pre-wrap;
    }
  }
}
</style> 