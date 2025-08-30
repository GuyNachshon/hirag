import { createRouter, createWebHistory } from 'vue-router'
import Chat from '../views/Chat.vue'
import Transcription from '../views/Transcription.vue'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      name: 'chat',
      component: Chat
    },
    {
      path: '/transcription',
      name: 'transcription',
      component: Transcription
    }
  ]
})

export default router
