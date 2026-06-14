<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import AppLayout from '@/components/AppLayout.vue'
import ErrorAlert from '@/components/ErrorAlert.vue'
import { fetchDevices } from '@/services/api/devices'
import { fetchSettings, updateSettings } from '@/services/api/settings'
import { getErrorMessage } from '@/services/api/errors'
import type { AppSettings, Device } from '@/types/api'

const devices = ref<Device[]>([])
const loading = ref(true)
const saving = ref(false)
const errorMessage = ref<string | null>(null)
const successMessage = ref<string | null>(null)

const form = reactive<AppSettings>({
  notificationsEnabled: true,
  temperatureUnit: 'celsius',
  noiseAlertThresholdDb: 70,
  defaultDeviceId: undefined,
})

async function loadPageData(): Promise<void> {
  loading.value = true
  errorMessage.value = null
  successMessage.value = null

  try {
    const [settings, deviceList] = await Promise.all([fetchSettings(), fetchDevices()])
    Object.assign(form, settings)
    devices.value = deviceList
  } catch (error) {
    errorMessage.value = getErrorMessage(error, 'Unable to load settings.')
  } finally {
    loading.value = false
  }
}

async function handleSave(): Promise<void> {
  saving.value = true
  errorMessage.value = null
  successMessage.value = null

  try {
    const updated = await updateSettings({ ...form })
    Object.assign(form, updated)
    successMessage.value = 'Settings saved successfully.'
  } catch (error) {
    errorMessage.value = getErrorMessage(error, 'Unable to save settings.')
  } finally {
    saving.value = false
  }
}

onMounted(() => {
  void loadPageData()
})
</script>

<template>
  <AppLayout title="Settings" subtitle="Manage alerts and device preferences.">
    <div class="mx-auto max-w-2xl space-y-6">
      <ErrorAlert v-if="errorMessage" title="Settings error" :message="errorMessage" />

      <div
        v-if="successMessage"
        class="rounded-lg border border-emerald-500/30 bg-emerald-500/10 px-4 py-3 text-sm text-emerald-200"
        role="status"
      >
        {{ successMessage }}
      </div>

      <form
        v-if="!loading"
        class="space-y-6 rounded-xl border border-white/10 bg-surface-900 p-6"
        @submit.prevent="handleSave"
      >
        <label class="flex items-center justify-between gap-4">
          <span>
            <span class="block text-sm font-medium text-white">Notifications</span>
            <span class="block text-sm text-gray-400">Receive alerts for threshold breaches.</span>
          </span>
          <input
            v-model="form.notificationsEnabled"
            type="checkbox"
            class="h-5 w-5 rounded border-white/20 bg-surface-950 text-accent-500 focus:ring-accent-500/30"
          />
        </label>

        <label class="block">
          <span class="mb-1.5 block text-sm font-medium text-gray-300">Temperature unit</span>
          <select
            v-model="form.temperatureUnit"
            class="w-full rounded-lg border border-white/10 bg-surface-950 px-3 py-2.5 text-white outline-none focus:border-accent-500"
          >
            <option value="celsius">Celsius</option>
            <option value="fahrenheit">Fahrenheit</option>
          </select>
        </label>

        <label class="block">
          <span class="mb-1.5 block text-sm font-medium text-gray-300">Noise alert threshold (dB)</span>
          <input
            v-model.number="form.noiseAlertThresholdDb"
            type="number"
            min="0"
            max="140"
            step="1"
            class="w-full rounded-lg border border-white/10 bg-surface-950 px-3 py-2.5 text-white outline-none focus:border-accent-500"
          />
        </label>

        <label class="block">
          <span class="mb-1.5 block text-sm font-medium text-gray-300">Default device</span>
          <select
            v-model="form.defaultDeviceId"
            class="w-full rounded-lg border border-white/10 bg-surface-950 px-3 py-2.5 text-white outline-none focus:border-accent-500"
          >
            <option :value="undefined">None</option>
            <option v-for="device in devices" :key="device.id" :value="device.id">
              {{ device.name }}
            </option>
          </select>
        </label>

        <button
          type="submit"
          class="rounded-lg bg-accent-500 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-accent-600 disabled:cursor-not-allowed disabled:opacity-60"
          :disabled="saving"
        >
          {{ saving ? 'Saving…' : 'Save settings' }}
        </button>
      </form>

      <div v-else class="rounded-xl border border-white/10 bg-surface-900 px-5 py-12 text-center text-gray-400">
        Loading settings…
      </div>
    </div>
  </AppLayout>
</template>
