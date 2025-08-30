<script setup>
import { ref, computed } from 'vue';
import {
  PopoverRoot,
  PopoverTrigger,
  PopoverContent,
} from 'radix-vue'
import {
  TooltipProvider,
  TooltipRoot as Tooltip,
  TooltipTrigger,
  TooltipContent,
} from 'radix-vue'
import {
  DialogRoot as Dialog,
  DialogTrigger,
  DialogContent,
  DialogClose,
  DialogTitle,
  DialogDescription,
} from 'radix-vue'


import { ArrowUp, Plus, Settings2, X, Bot, AudioLines, DatabaseZap, File, Image } from 'lucide-vue-next';

const fileInputRef = ref(null);
const isImageDialogOpen = ref(false);
const imagePreview = ref(null);
const internalTextareaRef = ref(null);
const internalTextareaValue = ref('');
const selectedMode = ref('chatMode');
const isPopoverOpen = ref(false);
const isSending = ref(false);
const selectedFiles = ref([]);
const isUploading = ref(false);

const modes = [
  {
    id: "chatMode",
    name: 'צ׳אט',
    icon: Bot,
  },
  {
    id: "transcribeMode",
    name: 'תמלול',
    icon: AudioLines,
  },
  {
    id: "documentMode",
    name: 'מסמכים',
    icon: DatabaseZap,
  },
];

const handleFileChange = (event) => {
  const files = Array.from(event.target.files);
  
  files.forEach(file => {
    // Check file size (max 10MB)
    if (file.size > 10 * 1024 * 1024) {
      alert('קובץ גדול מדי. הגודל המקסימלי הוא 10MB');
      return;
    }
    
    // Check file type
    const allowedTypes = [
      'image/jpeg', 'image/png', 'image/gif', 'image/webp',
      'application/pdf', 'text/plain', 'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    ];
    
    if (!allowedTypes.includes(file.type)) {
      alert('סוג קובץ לא נתמך');
      return;
    }
    
    // Add file to selected files
    selectedFiles.value.push({
      file: file,
      id: Date.now() + Math.random(),
      name: file.name,
      size: file.size,
      type: file.type
    });
    
    // If it's an image, create preview
    if (file.type.startsWith('image/')) {
      const reader = new FileReader();
      reader.onload = (e) => {
        const fileObj = selectedFiles.value.find(f => f.file === file);
        if (fileObj) {
          fileObj.preview = e.target.result;
        }
      };
      reader.readAsDataURL(file);
    }
  });
  
  // Clear the input
  event.target.value = '';
};

function handleRemoveFile(fileId) {
  const index = selectedFiles.value.findIndex(f => f.id === fileId);
  if (index !== -1) {
    selectedFiles.value.splice(index, 1);
  }
}

function handleRemoveImage() {
  imagePreview.value = null;
  isImageDialogOpen.value = false;
}

function handleTextareaChange(event) {
  console.log('textarea changed');
  internalTextareaValue.value = event.target.value;
}

function handleKeydown(event) {
  if (event.key === 'Enter' && !event.shiftKey) {
    event.preventDefault();
    handleSendMessage();
  }
}

function handleModeChange(mode) {
  selectedMode.value = mode.id;
  isPopoverOpen.value = false;
}

function handlePlusClick() {
  fileInputRef.value.click();
}

const hasValue = computed(() => {
  return internalTextareaValue.value.trim() !== '' || selectedFiles.value.length > 0;
});

const emit = defineEmits(['message-sent']);

const handleSendMessage = async () => {
  if (hasValue.value) {
    isSending.value = true;
    const messageContent = internalTextareaValue.value;
    const files = selectedFiles.value.map(f => f.file);
    
    // Clear the textarea and files
    internalTextareaValue.value = '';
    selectedFiles.value = [];
    
    // Emit the message-sent event with the message content and files
    emit('message-sent', messageContent, files);
    
    // Reset sending state after a short delay
    setTimeout(() => {
      isSending.value = false;
    }, 100);
  }
};

const formatFileSize = (bytes) => {
  if (bytes === 0) return '0 Bytes';
  const k = 1024;
  const sizes = ['Bytes', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
};

</script>

<template>
  <div class="prompt-box">
    <input 
      type="file" 
      accept="image/*,.pdf,.txt,.doc,.docx" 
      multiple
      ref="fileInputRef" 
      @change="handleFileChange" 
      class="prompt-box__input"
    >
    
    <!-- File previews -->
    <div v-if="selectedFiles.length > 0" class="prompt-box__files">
      <div 
        v-for="fileObj in selectedFiles" 
        :key="fileObj.id" 
        class="prompt-box__files__item"
      >
        <div class="prompt-box__files__item__preview">
          <img 
            v-if="fileObj.preview" 
            :src="fileObj.preview" 
            :alt="fileObj.name"
            class="prompt-box__files__item__preview__image"
          />
          <div v-else class="prompt-box__files__item__preview__icon">
            <File v-if="fileObj.type === 'application/pdf'" />
            <Image v-else />
          </div>
        </div>
        <div class="prompt-box__files__item__info">
          <div class="prompt-box__files__item__info__name">{{ fileObj.name }}</div>
          <div class="prompt-box__files__item__info__size">{{ formatFileSize(fileObj.size) }}</div>
        </div>
        <button 
          @click="handleRemoveFile(fileObj.id)"
          class="prompt-box__files__item__remove"
          aria-label="Remove file"
        >
          <X />
        </button>
      </div>
    </div>
    
    <Dialog v-if="imagePreview" :open="isImageDialogOpen" @update:open="isImageDialogOpen = $event">
      <div class="prompt-box__image-preview">
        <button
          type="button"
          class="prompt-box__image-preview__button"
          @click="isImageDialogOpen = true"
        >
          <img
            :src="imagePreview"
            alt="Image preview"
            class="prompt-box__image-preview__button__image"
          />
        </button>

        <button
          @click="handleRemoveImage"
          class="prompt-box__image-preview__button__remove"
          aria-label="Remove image"
        >
          <X class="prompt-box__image-preview__button__remove__icon" />
        </button>
      </div>

      <DialogContent>
        <img
          :src="imagePreview"
          alt="Full size preview"
          class="prompt-box__image-preview__dialog-content__image"
        />
      </DialogContent>
    </Dialog>
    
    <textarea 
      class="prompt-box__textarea" 
      ref="internalTextareaRef" 
      rows="1" 
      v-model="internalTextareaValue" 
      @change="handleTextareaChange" 
      @keydown="handleKeydown" 
      placeholder="תשאלו חופשי"
      :disabled="isSending"
    />
    
    <div class="prompt-box__bottom">
      <TooltipProvider :delay-duration="100">
        <div class="prompt-box__bottom__tooltip">
          <!-- Attach file -->
          <Tooltip>
            <TooltipTrigger as-child>
              <button 
                class="prompt-box__bottom__tooltip__button" 
                type="button" 
                @click="handlePlusClick"
                :disabled="isSending"
              >
                <Plus class="prompt-box__bottom__tooltip__button__icon--plus" />
              </button>
            </TooltipTrigger>
            <TooltipContent side="bottom" :show-arrow="true" class="tooltip-content">
              <p>העלאת קובץ</p>
            </TooltipContent>
          </Tooltip>
          
          <!-- Modes -->
          <PopoverRoot :open="isPopoverOpen" @update:open="isPopoverOpen = $event">
            <Tooltip>
              <TooltipTrigger as-child>
                <PopoverTrigger as-child>
                  <button 
                    class="prompt-box__bottom__tooltip__button" 
                    type="button"
                    :disabled="isSending"
                  >
                    <Settings2 class="prompt-box__bottom__tooltip__button__icon" />
                    <span class="prompt-box__bottom__tooltip__button__name">מצבים</span>
                  </button>
                </PopoverTrigger>
              </TooltipTrigger>
              <TooltipContent side="bottom" :show-arrow="true" class="tooltip-content">
                <p>מצבים</p>
              </TooltipContent>
              <PopoverContent side="bottom" :show-arrow="true" class="popover-content">
                <div class="prompt-box__bottom__tooltip__popover">
                  <button 
                    v-for="mode in modes" 
                    :key="mode.id" 
                    class="prompt-box__bottom__tooltip__popover__button" 
                    type="button" 
                    @click="handleModeChange(mode)"
                  >
                    <component :is="mode.icon" class="prompt-box__bottom__tooltip__popover__button__icon" />
                    <span class="prompt-box__bottom__tooltip__popover__button__name">{{ mode.name }}</span>
                  </button>
                </div>
              </PopoverContent>
            </Tooltip>
          </PopoverRoot>

          <!-- Left side buttons -->
           <div class="prompt-box__bottom__right">
            <Tooltip>
              <TooltipTrigger as-child>
                <button 
                  class="prompt-box__bottom__right__button" 
                  type="submit" 
                  :disabled="!hasValue || isSending" 
                  @click="handleSendMessage"
                >
                  <ArrowUp class="prompt-box__bottom__right__button__icon" />
                </button>
              </TooltipTrigger>
              <TooltipContent side="bottom" :show-arrow="true" class="tooltip-content">
                <p>{{ isSending ? 'שולח...' : 'שליחה' }}</p>
              </TooltipContent>
            </Tooltip>
           </div>
        </div>
      </TooltipProvider>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '../assets/variables.scss' as *;

.prompt-box {
  display: flex;
  flex-direction: column;
  width: 100%;
  border-radius: 28px;
  padding: calc($spacing * 2);
  box-shadow: $drop-shadow-sm;
  background-color: $color-white;
  direction: rtl;
  font-family: $font-main;
  border: $border-main;

  transition-property: color, background-color, border-color, text-decoration-color, fill, stroke;
  transition-timing-function: $ease-in-out;
  transition-duration: 150ms;

  cursor: text;

  // darkmode
  &.dark {
    background-color: $color-dark-mode;
    border: none;
  }

  &__input {
    display: none;
  }

  &__image-preview {
    position: relative;
    width: fit-content;
    border-radius: 1rem;
    padding: $spacing $spacing 0 $spacing;
    margin-bottom: $spacing;

    &__button {
      transition: transform $ease-in-out 150ms;
      outline: none;
      border: none;

      &:hover {
        transform: scale(1.05);
      }

      &__image {
        width: calc($spacing * 14.5);
        height: calc($spacing * 14.5);
        border-radius: 1rem;
      }

      &__remove {
        position: absolute;
        right: calc($spacing * 2);
        top: calc($spacing * 2);
        z-index: 10;
        display: flex;
        height: calc($spacing * 4);
        width: calc($spacing * 4);
        align-items: center;
        justify-content: center;
        border-radius: $radius-full;
        background-color: rgba($color-white, 0.5);
        color: $color-black;
        transition: background-color $ease-in-out 150ms, color $ease-in-out 150ms;

        &:hover {
          background-color: rgba($color-white, 0.7);
        }

        &.dark {
          background-color: rgba($color-dark-mode, 0.5);
          color: $color-white;

          &:hover {
            background-color: $color-dark-mode-hover;
          }
        }

        &__icon {
          width: calc($spacing * 4);
          height: calc($spacing * 4);
        }
      }

      &__dialog-content {
        &__image {
          width: 100%;
          max-height: 95vh;
          object-fit: contain;
          border-radius: 24px;
        }
      }
    }
  }

  &__bottom {
    margin-top: calc($spacing * 0.5);
    padding: 0 $spacing $spacing $spacing;

    &__tooltip {
      display: flex;
      align-items: center;
      gap: calc($spacing * 2);

      &__button {
        display: flex;
        height: calc($spacing * 8);
        align-items: center;
        gap: calc($spacing * 2);
        padding: calc($spacing * 2);
        border-radius: $radius-full;
        font-size: $text-sm;
        color: $color-text-primary;
        transition-property: color, background-color, border-color, text-decoration-color, fill, stroke;
        transition-timing-function: $ease-in-out;
        transition-duration: 150ms;
        background-color: $color-white;
        outline: none;
        border: none;

        &:focus {
          outline: none;
          border: none;
        }

        &:hover {
          background-color: $color-bg-accent;
        }

        &.dark {
          color: $color-white;
          background-color: $color-dark-mode;

          &:hover {
            background-color: $color-dark-mode-hover;
          }
        }

        &__icon {
          width: calc($spacing * 4);
          height: calc($spacing * 4);

          &--plus {
            width: calc($spacing * 6);
            height: calc($spacing * 6);
          }
        }
      }

      &__popover {
        display: flex;
        flex-direction: column;
        gap: $spacing;


        &__button {
          outline: none;
          border: none;
          display: flex;
          align-items: center;
          width: 100%;
          gap: calc($spacing * 2);
          padding: calc($spacing * 2);
          border-radius: $radius-md;
          background-color: $color-white;
          text-align: right;
          font-size: $text-sm;
          font-family: $font-main;
          font-weight: $font-weight-light;

          &:hover {
            background-color: $color-bg-accent;
          }

          &.dark {
            background-color: $color-dark-mode;
          }

          &__icon {
            width: calc($spacing * 4);
            height: calc($spacing * 4);
          }
        }
      }
    }

    &__active-mode {

      &__gap {
        height: calc($spacing * 4);
        width: 100%;
        width: 1px;
        background-color: transparent;
      }

      &__button {
        outline: none;
        border: none;
        display: flex;
        align-items: center;
        height: calc($spacing * 8);
        align-items: center;
        gap: calc($spacing * 2);
        padding: calc($spacing * 2);
        border-radius: $radius-full;
        padding: 0 calc($spacing * 2);
        font-size: $text-sm;
        color: #2294ff;
        cursor: pointer;
        transition-property: color, background-color, border-color, text-decoration-color, fill, stroke;
        transition-timing-function: $ease-in-out;
        transition-duration: 150ms;

        &:hover {
          background-color: $color-bg-accent;
        }

        &.dark {
          background-color: #3b4045;
          color: #99ceff;
        }

        &__icon {
          width: calc($spacing * 4);
          height: calc($spacing * 4);
        }

        &__icon--close {
          width: calc($spacing * 4);
          height: calc($spacing * 4);
        }
      }
    }

    &__right {
      display: flex;
      align-items: center;
      gap: calc($spacing * 2);
      margin-right: auto;

      &__button {
        outline: none;
        border: none;
        display: flex;
        height: calc($spacing * 8);
        width: calc($spacing * 8);
        align-items: center;
        justify-content: center;
        border-radius: $radius-full;
        font-size: $text-sm;
        background-color: $color-black;
        color: $color-white;

        transition-property: color, background-color, border-color, text-decoration-color, fill, stroke;
        transition-timing-function: $ease-in-out;
        transition-duration: 150ms;

        &:focus-visible {
          outline: none;
          border: none;
        }

        &:disabled {
          pointer-events: none;
          background-color: rgba($color-black, 0.4);
        }
        
        &:hover {
          background-color: rgba($color-black, 0.8);
        }

        &.dark {
          background-color: $color-white;
          color: $color-black;

          &:hover {
            background-color: rgba($color-white, 0.8);
          }

          &:disabled {
            background-color: #515151;
          }
        }

        &__icon {
          width: calc($spacing * 6);
          height: calc($spacing * 6);
          font-weight: $font-weight-bold;
        }

        &__name {
        }
      }
    }
  }

  &__textarea {
    width: 100%;
    resize: none;
    border: none;
    background-color: transparent;
    font-size: $text-sm;
    font-family: $font-main;
    font-weight: $font-weight-light;
    padding: calc($spacing * 3);
    color: $color-text-primary;
    min-height: calc($spacing * 12);

    &:focus {
      outline: none;
      border: none;
    }

    &::placeholder {
      color: $color-gray-797;
      font-family: $font-main;
      font-weight: $font-weight-light;
    }


    &.dark {
      background-color: $color-dark-mode;
      color: $color-white;

      &::placeholder {
        color: oklch(87.2% 0.01 258.338);
      }
    }
  }

  &__files {
    display: flex;
    flex-wrap: wrap;
    gap: $spacing;
    margin-top: $spacing;
    padding: $spacing;
    border: $border-main;
    border-radius: $radius-md;
    background-color: $color-bg-accent;

    &.dark {
      background-color: $color-dark-mode-hover;
      border: none;
    }

    &__item {
      display: flex;
      align-items: center;
      gap: $spacing;
      padding: $spacing;
      border-radius: $radius-md;
      background-color: $color-white;
      border: $border-main;

      &.dark {
        background-color: $color-dark-mode;
        border: none;
      }

      &__preview {
        width: calc($spacing * 10);
        height: calc($spacing * 10);
        border-radius: $radius-md;
        overflow: hidden;
        display: flex;
        align-items: center;
        justify-content: center;
        background-color: $color-gray-f7f;

        &.dark {
          background-color: $color-dark-mode-hover;
        }

        &__image {
          width: 100%;
          height: 100%;
          object-fit: cover;
        }

        &__icon {
          width: calc($spacing * 6);
          height: calc($spacing * 6);
          color: $color-text-primary;
        }
      }

      &__info {
        flex-grow: 1;
        display: flex;
        flex-direction: column;
        gap: $spacing * 0.5;

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

      &__remove {
        background-color: $color-red;
        color: $color-white;
        border-radius: $radius-full;
        width: calc($spacing * 4);
        height: calc($spacing * 4);
        display: flex;
        align-items: center;
        justify-content: center;
        border: none;
        cursor: pointer;
        transition: background-color $ease-in-out 150ms;

        &:hover {
          background-color: $color-red-hover;
        }

        &.dark {
          background-color: $color-red;
          color: $color-white;

          &:hover {
            background-color: $color-red-hover;
          }
        }
      }
    }
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

  &.dark {
    background-color: $color-dark-mode;
    color: $color-white;
  }
}

:global(.popover-content) {
  background: $color-white !important;
  border: $border-main;
  border-radius: $radius-lg;
  box-shadow: $drop-shadow-sm;
  padding: calc($spacing * 2);
  animation: popoverFadeIn 0.2s ease-out;
  transform-origin: top center;
  direction: rtl;
  font-family: $font-main;

  &.dark {
    background-color: $color-dark-mode;
    border: none;
  }
}

@keyframes popoverFadeIn {
  from {
    opacity: 0;
    transform: scale(0.95) translateY(4px);
  }
  to {
    opacity: 1;
    transform: scale(1) translateY(0);
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