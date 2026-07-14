<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import AppLayout from '@/components/AppLayout.vue'
import CameraPanel from '@/components/CameraPanel.vue'
import ErrorAlert from '@/components/ErrorAlert.vue'
import { fetchDevices } from '@/services/api/devices'
import { getErrorMessage } from '@/services/api/errors'
import type { Device } from '@/types/api'

const devices = ref<Device[]>([])
const selectedDeviceId = ref('')
const loadingDevices = ref(true)
const errorMessage = ref<string | null>(null)

const selectedDevice = computed(() =>
  devices.value.find((device) => device.id === selectedDeviceId.value),
)

async function loadDevices(): Promise<void> {
  loadingDevices.value = true
  errorMessage.value = null

  try {
    devices.value = await fetchDevices()
    if (!selectedDeviceId.value && devices.value.length > 0) {
      selectedDeviceId.value = devices.value[0].id
    }
  } catch (error) {
    errorMessage.value = getErrorMessage(error, 'Unable to load devices.')
  } finally {
    loadingDevices.value = false
  }
}

onMounted(async () => {
  await loadDevices()
})
</script>

<template>
  <AppLayout title="Camera Stream" subtitle="Live feed from your selected device.">
    <div class="space-y-6">
      <div class="flex flex-wrap items-end gap-4">
        <label class="min-w-64 flex-1">
          <span class="mb-1.5 block text-sm font-medium text-gray-300">Device</span>
          <select
            v-model="selectedDeviceId"
            class="w-full rounded-lg border border-white/10 bg-surface-900 px-3 py-2.5 text-white outline-none focus:border-accent-500"
            :disabled="loadingDevices || devices.length === 0"
          >
            <option v-if="devices.length === 0" value="">No devices available</option>
            <option v-for="device in devices" :key="device.id" :value="device.id">
              {{ device.name }}
            </option>
          </select>
        </label>
      </div>

      <ErrorAlert v-if="errorMessage" title="Stream unavailable" :message="errorMessage" />

      <CameraPanel
        :device-id="selectedDeviceId"
        :device-name="selectedDevice?.name"
      />
    </div>
  </AppLayout>
</template>
