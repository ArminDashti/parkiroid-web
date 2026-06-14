<script setup lang="ts">
import { computed } from 'vue'
import { RouterLink, useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const route = useRoute()
const router = useRouter()
const authStore = useAuthStore()

const navigation = [
  { label: 'Dashboard', to: '/dashboard', icon: '▦' },
  { label: 'Stream', to: '/stream', icon: '▶' },
  { label: 'Gallery', to: '/gallery', icon: '▣' },
  { label: 'Metrics', to: '/metrics', icon: '◔' },
  { label: 'Settings', to: '/settings', icon: '⚙' },
]

const activePath = computed(() => route.path)

async function handleLogout(): Promise<void> {
  await authStore.logout()
  await router.push({ name: 'login' })
}
</script>

<template>
  <aside class="flex w-64 shrink-0 flex-col border-r border-white/10 bg-surface-900">
    <div class="border-b border-white/10 px-6 py-5">
      <p class="text-xs font-semibold uppercase tracking-[0.2em] text-accent-500">Parkiroid</p>
      <p class="mt-1 text-lg font-semibold text-white">Control Center</p>
    </div>

    <nav class="flex-1 space-y-1 p-4">
      <RouterLink
        v-for="item in navigation"
        :key="item.to"
        :to="item.to"
        class="flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition"
        :class="
          activePath === item.to || activePath.startsWith(item.to + '/')
            ? 'bg-accent-500/15 text-accent-500'
            : 'text-gray-300 hover:bg-white/5 hover:text-white'
        "
      >
        <span aria-hidden="true" class="text-base">{{ item.icon }}</span>
        {{ item.label }}
      </RouterLink>
    </nav>

    <div class="border-t border-white/10 p-4">
      <p class="truncate text-sm font-medium text-white">
        {{ authStore.user?.name ?? authStore.user?.email ?? 'Signed in' }}
      </p>
      <p v-if="authStore.user?.email" class="truncate text-xs text-gray-400">
        {{ authStore.user.email }}
      </p>
      <button
        type="button"
        class="mt-3 w-full rounded-lg border border-white/10 px-3 py-2 text-sm text-gray-300 transition hover:border-white/20 hover:bg-white/5 hover:text-white"
        :disabled="authStore.loading"
        @click="handleLogout"
      >
        Sign out
      </button>
    </div>
  </aside>
</template>
