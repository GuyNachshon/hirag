<script setup>
import { useChatStore } from '../stores/chat.js'
import PromptBox from '../components/PromptBox.vue'
import ChatTurn from '../components/ChatTurn.vue'
import { onMounted, ref, watch, nextTick } from 'vue'
const chatStore = useChatStore()

// Auto-scroll handling
const messagesContainer = ref(null)
const scrollToBottom = () => {
  const el = messagesContainer.value
  if (!el) return
  el.scrollTo({ top: el.scrollHeight, behavior: 'smooth' })
}

const handleMessageSent = async (messageContent, useRag = true, files = []) => {
  try {
    await chatStore.sendMessage(messageContent, useRag, files)
  } catch (error) {
    console.error('Error sending message:', error)
    // You could show a toast notification here
  }
}

const handleEditMessage = async (messageId, newContent) => {
  try {
    await chatStore.editMessage(messageId, newContent)
  } catch (error) {
    console.error('Error editing message:', error)
    // You could show a toast notification here
  }
}

// Initialize component when it mounts
onMounted(async () => {
  try {
    // Clear messages for new conversation
    await chatStore.clearMessages()
    
    // Load document stats
    await chatStore.loadDocumentStats()
    await nextTick()
    scrollToBottom()
  } catch (error) {
    console.error('Error initializing chat:', error)
  }
})

// Scroll when a new message is added
watch(() => chatStore.messages.length, async () => {
  await nextTick()
  scrollToBottom()
})

// Scroll as the last message streams
watch(
  () => chatStore.messages.length ? chatStore.messages[chatStore.messages.length - 1]?.content : '',
  async () => {
    await nextTick()
    scrollToBottom()
  }
)
</script>

<template>
  <div class="chat-wrapper" :class="{ 'chat-wrapper--message-sent': chatStore.hasMessageBeenSent }">
    <div class="chat">
      <div class="chat__header" v-show="!chatStore.hasMessageBeenSent">
        במה אוכל לעזור?
      </div>
      
      <!-- Error display -->
      <div v-if="chatStore.error" class="chat__error">
        {{ chatStore.error }}
      </div>
      
      <div class="chat__messages" v-if="chatStore.hasMessageBeenSent" ref="messagesContainer">
        <ChatTurn 
          v-for="message in chatStore.messages" 
          :key="message.id"
          :turn="{
            messageId: message.id,
            messageAuthorRole: message.sender,
            messageContent: message.content,
            messageFiles: message.files || [],
            isStreaming: message.isStreaming || false,
            timestamp: message.timestamp
          }"
          @edit-message="handleEditMessage"
        />
        
        <div v-if="chatStore.isLoading" class="chat__loading">
          <div class="chat__loading__dots">
            <div class="chat__loading__dot"></div>
            <div class="chat__loading__dot"></div>
            <div class="chat__loading__dot"></div>
          </div>
        </div>
      </div>
      
      <div class="chat__main" :class="{ 'chat__main--message-sent': chatStore.hasMessageBeenSent }">
        <PromptBox @message-sent="handleMessageSent" />
      </div>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '../assets/variables.scss' as *;

.chat-wrapper {
  display: flex;
  height: 100vh;
  min-height: 0;
  width: 100%;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: calc($spacing * 4);
  box-sizing: border-box;
  transition: all 0.3s ease-in-out;

  &--message-sent {
    justify-content: flex-start;
    padding-bottom: calc($spacing * 4);
  }
}

.chat {
  width: 100%;
  max-width: 60rem;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-direction: column;
  gap: calc($spacing * 10);
  transition: all 0.3s ease-in-out;
  height: 100%;
  min-height: 0; // allow children with overflow to scroll
  
  &__header {
    font-size: 1.75rem;
    font-weight: 400;
    font-family: $font-main;
    transition: opacity 0.3s ease-in-out;
  }

  &__error {
    background-color: #fee2e2;
    border: 1px solid #fecaca;
    color: #dc2626;
    padding: calc($spacing * 3);
    border-radius: $radius-md;
    font-family: $font-main;
    font-size: $text-sm;
    margin-bottom: calc($spacing * 4);
  }

  &__messages {
    width: 100%;
    flex: 1;
    overflow-y: auto;
    overscroll-behavior: contain;
    display: flex;
    flex-direction: column;
    gap: calc($spacing * 4);
    padding: calc($spacing * 4) 0;
    margin-bottom: calc($spacing * 4);
  }

  &__loading {
    display: flex;
    justify-content: flex-start;
    padding: calc($spacing * 3) calc($spacing * 4);
    
    &__dots {
      display: flex;
      gap: calc($spacing * 1);
    }
    
    &__dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background-color: $color-gray-797;
      animation: loadingDot 1.4s infinite ease-in-out;
      
      &:nth-child(1) { animation-delay: -0.32s; }
      &:nth-child(2) { animation-delay: -0.16s; }
      &:nth-child(3) { animation-delay: 0s; }
    }
  }

  &__main {
    width: 100%;
    margin: 1.5rem;
    padding-inline: 1.5rem;
    display: flex;
    justify-content: center;
    align-items: center;
    transition: all 0.3s ease-in-out;

    &--message-sent {
      margin: 0;
      padding-inline: 0;
    }

    &__composer {
      max-width: 60rem;
      gap: 1.25rem;
      display: flex;
      min-height: 3.5rem;

      &__inner {
        display: flex;
        align-items: flex-end;
        width: 100%;
        background: $color-white;
        border-radius: 28px;
      }
    }
  }
}

@keyframes loadingDot {
  0%, 80%, 100% {
    transform: scale(0.8);
    opacity: 0.5;
  }
  40% {
    transform: scale(1);
    opacity: 1;
  }
}
</style>
