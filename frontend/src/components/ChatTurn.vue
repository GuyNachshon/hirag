<script setup>
import { computed, defineProps, ref } from 'vue'
import { Copy, Edit, File, Image, Download } from 'lucide-vue-next'
import { TooltipRoot as Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from 'radix-vue'

const props = defineProps({
    turn: {
        type: Object,
        required: true
    }
})

const emit = defineEmits(['edit-message'])

const editingMessageId = ref(null)
const editingContent = ref('')

const messageAuthorRole = computed(() => {
    return props.turn.messageAuthorRole
})

const messageId = computed(() => {
    return props.turn.messageId
})

const messageContent = computed(() => {
    return props.turn.messageContent
})

const messageFiles = computed(() => {
    return props.turn.messageFiles || []
})

const isStreaming = computed(() => {
    return props.turn.isStreaming || false
})

const timestamp = computed(() => {
    return props.turn.timestamp
})

const isUserMessage = computed(() => {
    return messageAuthorRole.value === 'user'
})

const isAssistantMessage = computed(() => {
    return messageAuthorRole.value === 'assistant'
})

const copyMessage = (message) => {
    navigator.clipboard.writeText(message)
}

const startEditing = () => {
    editingMessageId.value = messageId.value
    editingContent.value = messageContent.value
}

const saveEdit = () => {
    if (editingContent.value.trim()) {
        emit('edit-message', messageId.value, editingContent.value.trim())
    }
    editingMessageId.value = null
    editingContent.value = ''
}

const cancelEdit = () => {
    editingMessageId.value = null
    editingContent.value = ''
}

const downloadFile = (file) => {
    if (file.url) {
        const link = document.createElement('a')
        link.href = file.url
        link.download = file.name
        document.body.appendChild(link)
        link.click()
        document.body.removeChild(link)
    }
}

const formatFileSize = (bytes) => {
    if (bytes === 0) return '0 Bytes'
    const k = 1024
    const sizes = ['Bytes', 'KB', 'MB', 'GB']
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
}

const getFileIcon = (fileType) => {
    if (fileType.startsWith('image/')) {
        return Image
    }
    return File
}

const formatTimestamp = (timestamp) => {
    if (!timestamp) return ''
    const date = new Date(timestamp)
    return date.toLocaleTimeString('he-IL', { 
        hour: '2-digit', 
        minute: '2-digit' 
    })
}
import { renderMarkdown } from '@/utils/markdown.js'

const renderedHtml = computed(() => renderMarkdown(messageContent.value))

</script>

<template>
<article class="chat-turn" dir="auto" data-testid="conversation-turn-2" data-scroll-anchor="false">
  <div class="chat-turn__body">
    <div class="chat-turn__container" :class="{ 
      'chat-turn__container--user': isUserMessage,
      'chat-turn__container--assistant': isAssistantMessage 
    }" tabindex="-1">
      <div class="chat-turn__message-container" :class="{ 
        'chat-turn__message-container--user': isUserMessage,
        'chat-turn__message-container--assistant': isAssistantMessage 
      }">
        <div class="chat-turn__message-content">
          <div class="chat-turn__bubble" :class="{ 
            'chat-turn__bubble--user': isUserMessage,
            'chat-turn__bubble--assistant': isAssistantMessage 
          }">
            <div class="chat-turn__text" :class="{ 
              'chat-turn__text--user': isUserMessage,
              'chat-turn__text--assistant': isAssistantMessage 
            }" :dir="'auto'" :data-message-author-role="messageAuthorRole" :data-message-id="messageId">
              <div class="chat-turn__markdown-wrapper">
                <div class="chat-turn__markdown">
                  <div v-if="editingMessageId === messageId" class="chat-turn__edit">
                    <textarea 
                      v-model="editingContent"
                      class="chat-turn__edit__textarea"
                      @keydown.enter.prevent="saveEdit"
                      @keydown.escape="cancelEdit"
                      rows="1"
                      autofocus
                    />
                    <div class="chat-turn__edit__buttons">
                      <button @click="saveEdit" class="chat-turn__edit__button chat-turn__edit__button--save">
                        שמור
                      </button>
                      <button @click="cancelEdit" class="chat-turn__edit__button chat-turn__edit__button--cancel">
                        ביטול
                      </button>
                    </div>
                  </div>
                  <div v-else>
                    <div v-html="renderedHtml" dir="auto"></div>
                    <div v-if="isStreaming" class="chat-turn__streaming-indicator">
                      <span class="chat-turn__streaming-dot"></span>
                    </div>
                  </div>
                </div>
              </div>
              
              <!-- File attachments -->
              <div v-if="messageFiles.length > 0" class="chat-turn__files">
                <div 
                  v-for="file in messageFiles" 
                  :key="file.id || file.name"
                  class="chat-turn__files__item"
                >
                  <div class="chat-turn__files__item__preview">
                    <img 
                      v-if="file.type && file.type.startsWith('image/') && file.url" 
                      :src="file.url" 
                      :alt="file.name"
                      class="chat-turn__files__item__preview__image"
                      @click="downloadFile(file)"
                    />
                    <div v-else class="chat-turn__files__item__preview__icon">
                      <component :is="getFileIcon(file.type)" />
                    </div>
                  </div>
                  <div class="chat-turn__files__item__info">
                    <div class="chat-turn__files__item__info__name">{{ file.name }}</div>
                    <div class="chat-turn__files__item__info__size">{{ formatFileSize(file.size) }}</div>
                  </div>
                  <button 
                    v-if="file.url"
                    @click="downloadFile(file)"
                    class="chat-turn__files__item__download"
                    aria-label="Download file"
                  >
                    <Download />
                  </button>
                </div>
              </div>
            </div>
          </div>

          <!-- Action buttons -->
          <!-- <div class="chat-turn__actions-wrapper" :class="{ 
            'chat-turn__actions-wrapper--user': isUserMessage,
            'chat-turn__actions-wrapper--assistant': isAssistantMessage 
          }">
            <div class="chat-turn__actions" :class="{ 
              'chat-turn__actions--user': isUserMessage,
              'chat-turn__actions--assistant': isAssistantMessage 
            }">
              <div class="chat-turn__actions-inner" :class="{ 
                'chat-turn__actions-inner--visible': isAssistantMessage 
              }">
                <TooltipProvider :delay-duration="100">
                  <Tooltip>
                    <TooltipTrigger as-child>
                      <button
                        aria-label="Copy"
                        class="chat-turn__action-button"
                        @click="copyMessage(messageContent)"
                      >
                        <Copy/>
                      </button>
                    </TooltipTrigger>
                    <TooltipContent side="top" :show-arrow="true" class="tooltip-content">
                      <p>העתק</p>
                    </TooltipContent>
                  </Tooltip>

                  <Tooltip v-if="isUserMessage">
                    <TooltipTrigger as-child>
                      <button
                        aria-label="Edit"
                        class="chat-turn__action-button"
                        @click="startEditing"
                      >
                        <Edit/>
                      </button>
                    </TooltipTrigger>
                    <TooltipContent side="top" :show-arrow="true" class="tooltip-content">
                      <p>ערוך</p>
                    </TooltipContent>
                  </Tooltip>
                </TooltipProvider>
              </div>
            </div>
          </div> -->
        </div>
      </div>
    </div>
  </div>
</article>

</template>

<style scoped lang="scss">
@use '../assets/variables.scss' as *;

.chat-turn {
    width: 100%;
    color: $color-text-primary;

    &__body {
        font-size: $text-base;
        padding-inline: calc($spacing * 6);
        margin-block: auto;
        margin-inline: auto;
    }

    &__container {
        display: flex;
        margin-inline: auto;
        max-width: 60rem;
        flex: 1;
        gap: calc($spacing * 4);
        
        @media (min-width: 768px) {
            gap: calc($spacing * 5);
        }

        @media (min-width: 1024px) {
            gap: calc($spacing * 6);
        }
        
        &--user {
            justify-content: flex-end;
            direction: rtl;
        }
        
        &--assistant {
            justify-content: flex-end;
            direction: ltr;
        }
    }

    &__message-container {
        position: relative;
        display: flex;
        min-width: 0;
        flex-direction: column;
        max-width: 70%;
        
        &--user {
            align-self: flex-start;
        }
        
        &--assistant {
            align-self: flex-end;
        }
    }

    &__message-content {
        position: relative;
        display: flex;
        flex-direction: column;
        gap: calc($spacing * 1);

        @media (min-width: 768px) {
            gap: calc($spacing * 3);
        }
    }

    &__bubble {
        display: flex;
        flex-direction: column;
        flex-grow: 1;
        max-width: 100%;
        
        &--user {
            .chat-turn__text {
                align-items: flex-start;
                
                .chat-turn__markdown {
                    background-color: $color-message-surface;
                    color: $color-text-primary;
                    border-radius: 18px;
                    padding: calc($spacing * 3) calc($spacing * 4);
                }
            }
        }
        
        &--assistant {
            .chat-turn__text {
                align-items: flex-end;
                
                .chat-turn__markdown {
                    color: $color-text-primary;
                    border-radius: 18px;
                    padding: calc($spacing * 3) calc($spacing * 4);
                }
            }
        }
    }

    &__text {
        display: flex;
        flex-direction: column;
        gap: calc($spacing * 2);
        min-height: calc($spacing * 8);
        position: relative;
        width: 100%;
        word-break: break-word;
        white-space: normal;
        text-align: start;
        
        &--user {
            text-align: start;
        }
        
        &--assistant {
            text-align: end;
        }
    }

    &__markdown-wrapper {
        display: flex;
        width: 100%;
        flex-direction: column;
        gap: calc($spacing * 1);

        &:first-child {
            padding-top: calc($spacing * 3);
        }

        &:empty {
            display: none;
        }
    }

    &__markdown {
        display: flex;
        width: 100%;
        flex-direction: column;
        gap: calc($spacing * 1);

        p {
            margin: 0;
        }
    }
    
    &__streaming-indicator {
        display: inline-flex;
        align-items: center;
        gap: calc($spacing * 1);
        margin-top: calc($spacing * 1);
        align-self: flex-start; // default for user (RTL)
    }
    
    &__streaming-dot {
        width: 4px;
        height: 4px;
        border-radius: 50%;
        background-color: $color-gray-797;
        animation: streamingDot 1.4s infinite ease-in-out;
    }
    
    // Place the streaming dots at the visual end per bubble side
    &__bubble--assistant {
        .chat-turn__streaming-indicator { align-self: flex-end; }
    }
    &__bubble--user {
        .chat-turn__streaming-indicator { align-self: flex-start; }
    }
    
    &__files {
        display: flex;
        flex-direction: column;
        gap: calc($spacing * 2);
        margin-top: calc($spacing * 2);
        
        &__item {
            display: flex;
            align-items: center;
            gap: calc($spacing * 2);
            padding: calc($spacing * 2);
            border-radius: $radius-md;
            background-color: $color-bg-accent;
            border: 1px solid $color-border;
            
            &__preview {
                width: calc($spacing * 8);
                height: calc($spacing * 8);
                border-radius: $radius-md;
                overflow: hidden;
                display: flex;
                align-items: center;
                justify-content: center;
                background-color: $color-white;
                
                &__image {
                    width: 100%;
                    height: 100%;
                    object-fit: cover;
                    cursor: pointer;
                    transition: transform 0.2s ease-in-out;
                    
                    &:hover {
                        transform: scale(1.05);
                    }
                }
                
                &__icon {
                    width: calc($spacing * 4);
                    height: calc($spacing * 4);
                    color: $color-text-primary;
                }
            }
            
            &__info {
                flex-grow: 1;
                display: flex;
                flex-direction: column;
                gap: calc($spacing * 0.5);
                
                &__name {
                    font-size: $text-sm;
                    font-weight: $font-weight-bold;
                    color: $color-text-primary;
                }
                
                &__size {
                    font-size: $text-xs;
                    color: $color-gray-797;
                }
            }
            
            &__download {
                background-color: $color-black;
                color: $color-white;
                border-radius: $radius-full;
                width: calc($spacing * 6);
                height: calc($spacing * 6);
                display: flex;
                align-items: center;
                justify-content: center;
                border: none;
                cursor: pointer;
                transition: background-color 0.2s ease-in-out;
                
                &:hover {
                    background-color: rgba($color-black, 0.8);
                }
                
                svg {
                    width: calc($spacing * 3);
                    height: calc($spacing * 3);
                }
            }
        }
    }
    
    &__timestamp {
        font-size: $text-xs;
        color: $color-gray-797;
        margin-top: calc($spacing * 1);
        text-align: end;
    }
    
    &__edit {
        display: flex;
        flex-direction: column;
        gap: calc($spacing * 2);
        
        &__textarea {
            width: 100%;
            min-height: calc($spacing * 8);
            padding: calc($spacing * 2);
            border: 1px solid $color-border;
            border-radius: $radius-md;
            font-family: $font-main;
            font-size: $text-sm;
            resize: vertical;
            
            &:focus {
                outline: none;
                border-color: $color-black;
            }
        }
        
        &__buttons {
            display: flex;
            gap: calc($spacing * 2);
            justify-content: flex-end;
        }
        
        &__button {
            padding: calc($spacing * 1.5) calc($spacing * 3);
            border-radius: $radius-md;
            font-family: $font-main;
            font-size: $text-sm;
            border: none;
            cursor: pointer;
            transition: all 0.2s ease-in-out;
            
            &--save {
                background-color: $color-black;
                color: $color-white;
                
                &:hover {
                    background-color: rgba($color-black, 0.8);
                }
            }
            
            &--cancel {
                background-color: $color-bg-accent;
                color: $color-text-primary;
                
                &:hover {
                    background-color: $color-border;
                }
            }
        }
    }

    &__actions-wrapper {
        // margin-inline: calc($spacing * 6);
        
        &--user {
            .chat-turn__actions {
                justify-content: flex-start;
            }
        }
        
        &--assistant {
            .chat-turn__actions {
                justify-content: flex-start;
            }
        }
    }

    &__actions {
        display: flex;
        min-height: 46px;
        justify-content: flex-start;
    }

    &__actions-inner {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        row-gap: calc($spacing * 4);
        // padding: calc($spacing * 1);
        pointer-events: none;
        opacity: 0;
        visibility: hidden;
        transition: opacity 0.2s ease-in-out, visibility 0.2s ease-in-out;

        &:hover {
            pointer-events: auto;
            opacity: 1;
            visibility: visible;
        }
        
        &--visible {
            opacity: 1;
            visibility: visible;
        }
    }

    &__action-button {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 46px;
        height: 46px;
        border-radius: $radius-lg;
        border: transparent;
        cursor: pointer;
        background: transparent;
        transition: all 0.2s ease-in-out;
        
        &:hover {
            transform: scale(1.05);
            background-color: rgba($color-white, 0.9);
            border: $border-main;

        }
        
        svg {
            width: calc($spacing * 3);
            height: calc($spacing * 3);
            color: $color-text-primary;
        }
    }
}

/* Basic markdown styling */
.chat-turn__markdown {
  :deep(*) { text-align: start; }
  :deep(h1), :deep(h2), :deep(h3), :deep(h4), :deep(h5), :deep(h6) {
    margin: 0.5rem 0;
    font-weight: 700;
  }
  :deep(ul) {
    margin: 0.5rem 1.25rem;
    padding: 0;
  }
  :deep(li) { margin: 0.25rem 0; }
  :deep(a) { color: #2563eb; text-decoration: underline; }
  :deep(code) { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; direction: ltr; }
  :deep(pre) {
    background: #0f172a0d;
    padding: 0.75rem;
    border-radius: 6px;
    overflow-x: auto;
    direction: ltr;
  }
}

/* Make bidi handling robust for mixed Hebrew/English */
.chat-turn__text {
  unicode-bidi: plaintext; /* derive base direction from content per block */
}

@keyframes streamingDot {
    0%, 80%, 100% {
        transform: scale(0.8);
        opacity: 0.5;
    }
    40% {
        transform: scale(1);
        opacity: 1;
    }
}

:global(.tooltip-content) {
    font-size: $text-xs;
    padding: calc($spacing * 2);
    margin-top: calc($spacing * 2);
    background-color: $color-white;
    color: $color-black;
    animation: tooltipFadeIn 0.2s ease-out;
    transform-origin: bottom center;
    border-radius: $radius-lg;
    border: 1px solid $color-border;
    box-shadow: $drop-shadow-sm;

    &.dark {
        background-color: $color-dark-mode;
        color: $color-white;
    }
}

@keyframes tooltipFadeIn {
    from {
        opacity: 0;
        transform: scale(0.95) translateY(-4px);
    }
    to {
        opacity: 1;
        transform: scale(1) translateY(0);
    }
}
</style>
