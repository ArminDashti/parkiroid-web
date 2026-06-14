import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { apiClient } from '@/services/api/client'
import * as authApi from '@/services/api/auth'
import type { User } from '@/types/api'
import { isApiError } from '@/services/api/errors'

const TOKEN_STORAGE_KEY = 'parkiroid.auth.token'

export const useAuthStore = defineStore('auth', () => {
  const token = ref<string | null>(localStorage.getItem(TOKEN_STORAGE_KEY))
  const user = ref<User | null>(null)
  const initialized = ref(false)
  const loading = ref(false)

  const isAuthenticated = computed(() => Boolean(token.value))

  apiClient.setTokenProvider(() => token.value)

  function persistToken(value: string | null): void {
    token.value = value

    if (value) {
      localStorage.setItem(TOKEN_STORAGE_KEY, value)
    } else {
      localStorage.removeItem(TOKEN_STORAGE_KEY)
    }
  }

  async function initializeSession(): Promise<void> {
    if (initialized.value) {
      return
    }

    initialized.value = true

    if (!token.value) {
      return
    }

    try {
      user.value = await authApi.fetchCurrentUser()
    } catch (error) {
      if (isApiError(error) && (error.status === 401 || error.status === 403)) {
        persistToken(null)
        user.value = null
      }
    }
  }

  async function login(email: string, password: string): Promise<void> {
    loading.value = true

    try {
      const response = await authApi.login({ email, password })
      persistToken(response.token)
      user.value = response.user
    } finally {
      loading.value = false
    }
  }

  async function logout(): Promise<void> {
    loading.value = true

    try {
      if (token.value) {
        await authApi.logout().catch(() => undefined)
      }
    } finally {
      persistToken(null)
      user.value = null
      loading.value = false
    }
  }

  return {
    token,
    user,
    initialized,
    loading,
    isAuthenticated,
    initializeSession,
    login,
    logout,
  }
})
