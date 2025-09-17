<script setup>
import { RouterLink, RouterView } from 'vue-router'
import { ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { useChatStore } from './stores/chat.js'

const router = useRouter()
const chatStore = useChatStore()

const isSidebarOpen = ref(false)

const toggleSidebar = () => {
  isSidebarOpen.value = !isSidebarOpen.value
  console.log(isSidebarOpen.value)
}

const navItems = [
  {
    name: 'צ׳אט',
    route: '/'
  },
  {
    name: 'חיפוש',
    route: '/search'
  },
  {
    name: 'תמלולים',
    route: '/transcription'
  },
]

const activeNavItem = ref(navItems[0])

// Watch for route changes to update active nav item
watch(() => router.currentRoute.value.path, (newPath) => {
  const matchingItem = navItems.find(item => item.route === newPath)
  if (matchingItem) {
    activeNavItem.value = matchingItem
  }
}, { immediate: true })

const handleNavItemClick = (item) => {
  activeNavItem.value = item
  router.push(item.route)
}

const newConversation = async () => {
  try {
    // Clear current conversation
    await chatStore.clearMessages()
    // Navigate to root (new conversation without ID)
    router.push('/')
  } catch (error) {
    console.error('Error creating new conversation:', error)
    router.push('/')
  }
}

</script>

<template>
  <div class="app-layout">
    <div
      class="sidebar"
      :class="{ expanded: isSidebarOpen }"
    >
      <div class="sidebar__nav">
        <div class="sidebar__nav__item sidebar__nav__item--toggle" @click="toggleSidebar">
          <svg width="20" height="18" viewBox="0 0 20 18" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M13.8763 1.63909C14.4292 1.64423 14.8815 1.65417 15.2685 1.68586C15.7412 1.72457 16.0758 1.78979 16.3413 1.8849L16.5865 1.99042C17.1247 2.26533 17.575 2.68326 17.889 3.19665L18.0146 3.42207C18.1688 3.72552 18.2669 4.11145 18.3184 4.74341C18.3706 5.38483 18.371 6.20526 18.371 7.36452V10.6355C18.371 11.7947 18.3706 12.6152 18.3184 13.2566C18.2669 13.8886 18.1688 14.2746 18.0146 14.5779L17.889 14.8034C17.575 15.3167 17.1247 15.7347 16.5865 16.0096L16.3413 16.1152C16.0758 16.2102 15.7411 16.2754 15.2685 16.3142C14.8818 16.3459 14.4298 16.3558 13.8775 16.361L13.8763 1.63909ZM4.91924e-07 10.6355C4.91924e-07 11.7678 -0.000366849 12.6664 0.058543 13.3897C0.110839 14.0308 0.212372 14.5892 0.431722 15.102L0.533376 15.3189C0.944275 16.1275 1.56963 16.8041 2.33705 17.2758L2.67434 17.4653C3.2447 17.7565 3.86784 17.8814 4.59864 17.9413C5.32026 18.0004 6.2164 18 7.34597 18H12.654C13.7835 18 14.6797 18.0004 15.4013 17.9413C16.0409 17.8889 16.5977 17.786 17.1092 17.566L17.3257 17.4653C18.1321 17.0534 18.8071 16.4263 19.2776 15.6571L19.4666 15.3189C19.7571 14.7471 19.8817 14.1224 19.9414 13.3897C20.0003 12.6664 20 11.7678 20 10.6355V7.36452C20 6.23211 20.0003 5.33367 19.9414 4.61033C19.8817 3.87761 19.7571 3.25293 19.4666 2.68107L19.2776 2.34294C18.8071 1.5737 18.1321 0.946698 17.3257 0.534777L17.1092 0.432855C16.5978 0.21299 16.0407 0.111142 15.4013 0.0587514C14.6797 -0.000343579 13.7835 4.5412e-08 12.654 4.5412e-08H7.34597C6.2164 4.5412e-08 5.32026 -0.000343579 4.59864 0.0587514C3.86784 0.11862 3.2447 0.243513 2.67434 0.534777L2.33705 0.724229C1.56975 1.19592 0.944275 1.87262 0.533376 2.68107L0.431722 2.89808C0.212372 3.41075 0.110839 3.96923 0.058543 4.61033C-0.000366849 5.33367 4.91924e-07 6.23211 4.91924e-07 7.36452V10.6355ZM12.2485 16.3669H7.34597C6.18958 16.3669 5.37121 16.3665 4.73141 16.3142C4.10116 16.2625 3.7161 16.1642 3.41347 16.0096L3.1886 15.8837C2.67642 15.5689 2.25964 15.1174 1.98542 14.5779L1.8801 14.3321C1.78518 14.0659 1.72015 13.7305 1.68157 13.2566C1.62927 12.6152 1.6289 11.7947 1.6289 10.6355V7.36452C1.6289 6.20526 1.62927 5.38483 1.68157 4.74341C1.72015 4.26957 1.7853 3.93403 1.8801 3.66788L1.98542 3.42207C2.25964 2.88253 2.67654 2.43111 3.1886 2.11632L3.41347 1.99042C3.7161 1.8358 4.10103 1.73749 4.73141 1.68586C5.37121 1.63345 6.18958 1.6331 7.34597 1.6331H12.2485L12.2473 1.63909L12.2485 16.3669Z" fill="black"/>
          </svg>
        </div>
        <div class="sidebar__nav__item" @click="newConversation">
          <svg width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M5.56022e-08 11.8736V8.26214C5.56022e-08 7.01258 -0.000392625 6.02031 0.0648219 5.22217C0.130903 4.41382 0.268621 3.72457 0.590033 3.09365L0.799048 2.7206C1.31949 1.87204 2.06619 1.18145 2.95808 0.727024L3.19753 0.61459C3.76326 0.371895 4.3792 0.258323 5.08668 0.200521C5.88478 0.135322 6.87604 0.135702 8.12547 0.135702H8.80281C9.30023 0.135702 9.70354 0.539232 9.70373 1.03658C9.70373 1.5341 9.30035 1.93746 8.80281 1.93746H8.12547C6.84645 1.93746 5.94122 1.93786 5.23353 1.99567C4.7108 2.03837 4.34051 2.11036 4.04687 2.21527L3.77566 2.33167C3.18046 2.63494 2.6823 3.09621 2.33498 3.6625L2.19607 3.9112C2.0255 4.24595 1.91703 4.67189 1.86005 5.36901C1.80222 6.07677 1.80184 6.98284 1.80184 8.26214V11.8736C1.80184 13.1529 1.80222 14.059 1.86005 14.7668C1.91703 15.4638 2.02551 15.8898 2.19607 16.2245L2.33498 16.4732C2.68229 17.0395 3.1805 17.5008 3.77566 17.804L4.04687 17.9205C4.34049 18.0254 4.71084 18.0961 5.23353 18.1387C5.94123 18.1966 6.84639 18.1983 8.12547 18.1983H11.7383C13.0174 18.1983 13.9226 18.1966 14.6303 18.1387C15.3272 18.0818 15.7535 17.9744 16.0882 17.804L16.3382 17.6638C16.9042 17.3166 17.366 16.8195 17.6692 16.2245L17.7855 15.9533C17.8905 15.6598 17.9611 15.2894 18.0038 14.7668C18.0616 14.059 18.062 13.1529 18.062 11.8736V11.1963C18.0622 10.6991 18.4657 10.2956 18.9629 10.2954C19.4603 10.2954 19.8636 10.699 19.8639 11.1963V11.8736C19.8639 13.1232 19.8656 14.1154 19.8004 14.9135C19.7425 15.6209 19.629 16.237 19.3862 16.8027L19.2738 17.042C18.8196 17.9337 18.1284 18.6794 17.2802 19.1997L16.9072 19.4087C16.276 19.7303 15.5859 19.8691 14.7772 19.9352C13.9791 20.0004 12.9878 20 11.7383 20H8.12547C6.87606 20 5.88477 20.0004 5.08668 19.9352C4.37922 19.8774 3.76325 19.7639 3.19753 19.5211L2.95808 19.4087C2.06625 18.9544 1.31948 18.2636 0.799048 17.4151L0.590033 17.042C0.268593 16.4112 0.130917 15.722 0.0648219 14.9135C-0.000392625 14.1154 5.56022e-08 13.1232 5.56022e-08 11.8736ZM14.625 0.738931C15.9194 -0.316703 17.8278 -0.241264 19.0344 0.96514L19.2606 1.21518C20.2463 2.4235 20.2466 4.16743 19.2606 5.37562L19.0344 5.62564L12.1975 12.4637C11.4723 13.1888 10.558 13.691 9.5635 13.9161L9.13355 13.9955L6.67157 14.3461C6.39096 14.386 6.10734 14.2925 5.9069 14.0921C5.7065 13.8916 5.61285 13.6081 5.6529 13.3275L6.00481 10.8668L6.08418 10.4357C6.30945 9.44134 6.81166 8.52686 7.53677 7.80178L14.3738 0.96514L14.625 0.738931ZM17.7605 2.23907C17.2134 1.69224 16.3482 1.65731 15.7615 2.13589L15.6477 2.23907L8.81075 9.07704C8.32686 9.56094 7.99134 10.1703 7.84104 10.8338L7.78811 11.1208L7.60556 12.3921L8.87822 12.2109L9.1653 12.1581C9.829 12.0077 10.4395 11.6723 10.9235 11.1883L17.7605 4.35171L17.8636 4.23795C18.3103 3.6902 18.3106 2.89918 17.8636 2.35152L17.7605 2.23907Z" fill="black"/>
          </svg>
          <div class="sidebar__nav__item__label" v-if="isSidebarOpen">
            שיחה חדשה
          </div>
        </div>
        <div class="sidebar__nav__item">
          <svg width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M15.9151 8.83946C15.9151 4.93176 12.7473 1.76401 8.83956 1.76401C4.93182 1.76401 1.76403 4.93176 1.76403 8.83946C1.76403 12.7471 4.93182 15.915 8.83956 15.915C12.7473 15.915 15.9151 12.7471 15.9151 8.83946ZM17.6792 8.83946C17.6792 10.9666 16.9261 12.917 15.6743 14.4423L15.7623 14.5162L19.7411 18.4949L19.855 18.6322C20.0812 18.9745 20.0424 19.4407 19.7411 19.7421C19.4396 20.0429 18.9745 20.0807 18.6324 19.8548L18.4938 19.7421L14.515 15.7634L14.4424 15.674C12.9172 16.9258 10.9668 17.6789 8.83956 17.6789C3.95763 17.6789 0 13.7214 0 8.83946C0 3.95759 3.95763 0 8.83956 0C13.7215 0 17.6792 3.95759 17.6792 8.83946Z" fill="black"/>
          </svg>
          <div class="sidebar__nav__item__label" v-if="isSidebarOpen">
            חיפוש בשיחות
          </div>
        </div>
    
      </div>
    </div>
    <div class="main-content" :class="{ 'sidebar-expanded': isSidebarOpen }">
      <nav class="nav">
        <div class="nav__item__logo"></div>
        <div class="nav__item__tabs">
          <div 
            class="nav__item__tabs__item" 
            v-for="item in navItems" 
            :key="item.name" 
            :class="{ 'active': activeNavItem.name === item.name }" 
            @click="handleNavItemClick(item)"
          >
            {{ item.name }}
          </div>
        </div>
        <div class="nav__item__login">
          <div class="nav__item__login__button">כניסה</div>
        </div>
      </nav>
      <router-view />
    </div>
  </div>
</template>

<style scoped lang="scss">
@use './assets/variables.scss' as *;

.app-layout {
  display: flex;
  flex-direction: row-reverse;
  height: 100vh;
}

.sidebar {
  width: 64px;
  min-width: 64px;
  max-width: 220px;
  transition: width 0.2s cubic-bezier(0.4,0,0.2,1);
  display: flex;
  flex-direction: column;
  justify-content: space-between;
  align-items: center;
  border-left: 1px solid $color-border;
  z-index: 10;
  padding: 20px 10px;
  
  &:hover {
  }

  &.expanded {
    width: 220px;
    min-width: 220px;
    transition: width 0.2s cubic-bezier(0.4,0,0.2,1);

  }

  &__nav {
    width: 100%;
    height: 100%;
    position: relative;
    display: flex;
    flex-direction: column;
    gap: 8px;
    align-items: flex-start;
    justify-content: flex-start;

    &__item {
      cursor: pointer;
      display: flex;
      align-items: center;
      gap: 10px;
      justify-content: flex-start;
      direction: rtl;
      width: 100%;
      padding-inline-end: 0;
      padding: 10px 10px 10px 0;
      border-radius: $radius-md;
      transition: padding 0.2s cubic-bezier(0.4,0,0.2,1), background-color 0.2s cubic-bezier(0.4,0,0.2,1);

      &:hover {
        background-color: $color-border;
      }
    }
  }
}

.main-content {
  flex: 1 1 0%;
  transition: margin-right 0.2s cubic-bezier(0.4,0,0.2,1);
  display: flex;
  flex-direction: column;
  min-width: 0;
  &.sidebar-expanded {
    margin-right: 220px;
  }
}

.nav {
  display: flex;
  flex-direction: row;
  justify-content: space-between;
  align-items: center;
  padding: 20px;
  font-family: $font-main;
  direction: rtl;

  &__item {

    &__logo {
      width: 100px;
      height: 40px;
    }

    &__tabs {
      display: flex;
      flex-direction: row;
      border-radius: $radius-3xl;
      border: $border-main;
      width: 206px;
      height: 40px;
      justify-content: space-around;
      align-items: center;
      box-shadow: 0px 2.17545px 5.43863px rgba(0, 0, 0, 0.1);

      &__item {
        cursor: pointer;
        font-size: $text-base;
        font-weight: $font-weight-regular;
        color: $color-gray-797;
        width: 100%;
        height: 100%;
        display: flex;
        align-content: center;
        justify-content: center;
        align-items: center;
        padding: 8px;

        &:nth-child(3) {
          border-radius: $radius-3xl 0 0 $radius-3xl;
        }
        &:nth-child(1) {
          border-radius: 0 $radius-3xl $radius-3xl 0;
        }

        &.active {
          background-color: $color-border;
          color: $color-black;
        }
      }
    }

    &__login {
      height: 40px;
      width: 100px;
      border-radius: $radius-3xl;
      background-color: $color-black;
      color: $color-white;
      display: flex;
      align-items: center;
      justify-content: center;
      cursor: pointer;
      line-height: 1;
    }
  }
}

.sidebar__nav__item--toggle {
  margin-bottom: 20px;
}

</style>
