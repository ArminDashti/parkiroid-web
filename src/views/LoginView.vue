<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import ErrorAlert from '@/components/ErrorAlert.vue'
import { useAuthStore } from '@/stores/auth'
import { getErrorMessage } from '@/services/api/errors'

const route = useRoute()
const router = useRouter()
const authStore = useAuthStore()

const email = ref('')
const password = ref('')
const errorMessage = ref<string | null>(null)

const redirectPath = computed(() => {
  const redirect = route.query.redirect
  return typeof redirect === 'string' && redirect.startsWith('/') ? redirect : '/dashboard'
})

async function handleSubmit(): Promise<void> {
  errorMessage.value = null

  if (!email.value || !password.value) {
    errorMessage.value = 'Enter your username and password.'
    return
  }

  try {
    await authStore.login(email.value.trim(), password.value)
    await router.replace(redirectPath.value)
  } catch (error) {
    errorMessage.value = getErrorMessage(error, 'Unable to sign in.')
  }
}
</script>

<template>
  <div class="flex min-h-screen items-center justify-center bg-surface-950 px-4">
    <div class="w-full max-w-md rounded-2xl border border-white/10 bg-surface-900 p-8 shadow-2xl">
      <div class="mb-8 text-center">
        <p class="text-xs font-semibold uppercase tracking-[0.2em] text-accent-500">Parkiroid</p>
        <h1 class="mt-2 text-2xl font-semibold text-white">Sign in</h1>
        <p class="mt-2 text-sm text-gray-400">Access your devices, streams, and metrics.</p>
      </div>

      <form class="space-y-4" @submit.prevent="handleSubmit">
        <ErrorAlert v-if="errorMessage" title="Sign in failed" :message="errorMessage" />

        <label class="block">
          <span class="mb-1.5 block text-sm font-medium text-gray-300">Email or username</span>
          <input
            v-model="email"
            type="text"
            autocomplete="username"
            required
            class="w-full rounded-lg border border-white/10 bg-surface-950 px-3 py-2.5 text-white outline-none transition focus:border-accent-500 focus:ring-2 focus:ring-accent-500/20"
            placeholder="armin"
          />
        </label>

        <label class="block">
          <span class="mb-1.5 block text-sm font-medium text-gray-300">Password</span>
          <input
            v-model="password"
            type="password"
            autocomplete="current-password"
            required
            class="w-full rounded-lg border border-white/10 bg-surface-950 px-3 py-2.5 text-white outline-none transition focus:border-accent-500 focus:ring-2 focus:ring-accent-500/20"
            placeholder="••••••••"
          />
        </label>

        <button
          type="submit"
          class="w-full rounded-lg bg-accent-500 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-accent-600 disabled:cursor-not-allowed disabled:opacity-60"
          :disabled="authStore.loading"
        >
          {{ authStore.loading ? 'Signing in…' : 'Sign in' }}
        </button>
      </form>
    </div>
  </div>
</template>
