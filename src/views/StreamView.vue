<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import AppLayout from '@/components/AppLayout.vue'
import ErrorAlert from '@/components/ErrorAlert.vue'
import { fetchDevices } from '@/services/api/devices'
import { fetchStreamUrl } from '@/services/api/stream'
import { getErrorMessage } from '@/services/api/errors'
import type { Device } from '@/types/api'

const devices = ref<Device[]>([])
const selectedDeviceId = ref('')
const streamUrl = ref<string | null>(null)
const loadingDevices = ref(true)
const loadingStream = ref(false)
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

async function loadStream(): Promise<void> {
  if (!selectedDeviceId.value) {
    streamUrl.value = null
    return
  }

  loadingStream.value = true
  errorMessage.value = null

  try {
    const response = await fetchStreamUrl(selectedDeviceId.value)
    streamUrl.value = response.streamUrl
  } catch (error) {
    streamUrl.value = null
    errorMessage.value = getErrorMessage(error, 'Unable to load stream URL.')
  } finally {
    loadingStream.value = false
  }
}

watch(selectedDeviceId, () => {
  void loadStream()
})

onMounted(async () => {
  await loadDevices()
  await loadStream()
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

      <section class="overflow-hidden rounded-xl border border-white/10 bg-surface-900">
        <div class="aspect-video bg-black">
          <video
            v-if="streamUrl"
            :key="streamUrl"
            class="h-full w-full object-cover"
            controls
            autoplay
            muted
            playsinline
            :src="streamUrl"
          >
            Your browser does not support embedded video streams.
          </video>

          <div
            v-else
            class="flex h-full flex-col items-center justify-center gap-2 px-6 text-center text-gray-400"
          >
            <p class="text-lg font-medium text-gray-300">
              {{ loadingStream ? 'Loading stream…' : 'No stream URL available' }}
            </p>
            <p class="text-sm">
              {{
                selectedDevice
                  ? `Waiting for a stream from ${selectedDevice.name}.`
                  : 'Select a device once your backend is connected.'
              }}
            </p>
          </div>
        </div>

        <div class="border-t border-white/10 px-5 py-4 text-sm text-gray-400">
          Stream URL is fetched from <code class="text-gray-300">GET /devices/:id/stream</code>.
        </div>
      </section>
    </div>
  </AppLayout>
</template>
