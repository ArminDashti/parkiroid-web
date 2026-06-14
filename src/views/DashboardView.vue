<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { RouterLink } from 'vue-router'
import AppLayout from '@/components/AppLayout.vue'
import ErrorAlert from '@/components/ErrorAlert.vue'
import { fetchDevices } from '@/services/api/devices'
import { getErrorMessage } from '@/services/api/errors'
import type { Device } from '@/types/api'

const devices = ref<Device[]>([])
const loading = ref(true)
const errorMessage = ref<string | null>(null)

const quickLinks = [
  { title: 'Live Stream', description: 'Watch the camera feed in real time.', to: '/stream' },
  { title: 'Image Gallery', description: 'Browse captured snapshots.', to: '/gallery' },
  { title: 'Device Metrics', description: 'Monitor temperature and noise levels.', to: '/metrics' },
  { title: 'Settings', description: 'Update alerts and preferences.', to: '/settings' },
]

onMounted(async () => {
  loading.value = true
  errorMessage.value = null

  try {
    devices.value = await fetchDevices()
  } catch (error) {
    errorMessage.value = getErrorMessage(error, 'Unable to load devices.')
  } finally {
    loading.value = false
  }
})

function statusClass(status: Device['status']): string {
  switch (status) {
    case 'online':
      return 'bg-emerald-500/15 text-emerald-300'
    case 'offline':
      return 'bg-red-500/15 text-red-300'
    default:
      return 'bg-gray-500/15 text-gray-300'
  }
}
</script>

<template>
  <AppLayout title="Dashboard" subtitle="Overview of your Parkiroid deployment.">
    <div class="space-y-6">
      <ErrorAlert v-if="errorMessage" title="Dashboard unavailable" :message="errorMessage" />

      <section class="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        <RouterLink
          v-for="link in quickLinks"
          :key="link.to"
          :to="link.to"
          class="rounded-xl border border-white/10 bg-surface-900 p-5 transition hover:border-accent-500/40 hover:bg-surface-800"
        >
          <h2 class="text-lg font-semibold text-white">{{ link.title }}</h2>
          <p class="mt-2 text-sm text-gray-400">{{ link.description }}</p>
        </RouterLink>
      </section>

      <section class="rounded-xl border border-white/10 bg-surface-900">
        <div class="border-b border-white/10 px-5 py-4">
          <h2 class="text-lg font-semibold text-white">Device status</h2>
          <p class="text-sm text-gray-400">Latest status from the API.</p>
        </div>

        <div v-if="loading" class="px-5 py-8 text-sm text-gray-400">Loading devices…</div>

        <div v-else-if="devices.length === 0" class="px-5 py-8 text-sm text-gray-400">
          No devices reported yet. Connect your backend or add devices to see status here.
        </div>

        <ul v-else class="divide-y divide-white/10">
          <li
            v-for="device in devices"
            :key="device.id"
            class="flex items-center justify-between gap-4 px-5 py-4"
          >
            <div>
              <p class="font-medium text-white">{{ device.name }}</p>
              <p class="text-sm text-gray-400">{{ device.location ?? device.id }}</p>
            </div>
            <span
              class="rounded-full px-3 py-1 text-xs font-semibold uppercase tracking-wide"
              :class="statusClass(device.status)"
            >
              {{ device.status }}
            </span>
          </li>
        </ul>
      </section>
    </div>
  </AppLayout>
</template>
