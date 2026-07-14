<script setup lang="ts">
import { computed, onUnmounted, ref, watch } from 'vue'
import { Room, RoomEvent, Track } from 'livekit-client'
import { captureDeviceFrame } from '@/services/api/capture'
import { fetchStreamCredentials } from '@/services/api/stream'
import { getErrorMessage } from '@/services/api/errors'

export type ConnectionState = 'idle' | 'connecting' | 'live' | 'error'

const props = defineProps<{
  deviceId: string
  deviceName?: string
}>()

const emit = defineEmits<{
  connectionStateChange: [state: ConnectionState]
  captureSuccess: [message: string]
  error: [message: string]
}>()

const connectionState = ref<ConnectionState>('idle')
const loadingStream = ref(false)
const capturing = ref(false)
const captureMessage = ref<string | null>(null)
const errorMessage = ref<string | null>(null)
const videoContainer = ref<HTMLDivElement | null>(null)

let room: Room | null = null

const statusLabel = computed(() => {
  switch (connectionState.value) {
    case 'connecting':
      return 'Connecting to LiveKit…'
    case 'live':
      return 'Live'
    case 'error':
      return 'Connection failed'
    default:
      return loadingStream.value ? 'Loading stream…' : 'Not connected'
  }
})

const canPlay = computed(
  () => Boolean(props.deviceId) && connectionState.value !== 'connecting' && connectionState.value !== 'live',
)
const canStop = computed(() => connectionState.value === 'live' || connectionState.value === 'connecting')
const canCapture = computed(() => Boolean(props.deviceId) && connectionState.value === 'live' && !capturing.value)

function clearMediaElements(): void {
  if (videoContainer.value) {
    videoContainer.value.replaceChildren()
  }
}

async function disconnectStream(): Promise<void> {
  if (room) {
    room.removeAllListeners()
    await room.disconnect()
    room = null
  }
  clearMediaElements()
  connectionState.value = 'idle'
  emit('connectionStateChange', connectionState.value)
}

async function playStream(): Promise<void> {
  if (!props.deviceId || connectionState.value === 'connecting' || connectionState.value === 'live') {
    return
  }

  loadingStream.value = true
  errorMessage.value = null
  captureMessage.value = null
  connectionState.value = 'connecting'
  emit('connectionStateChange', connectionState.value)

  try {
    await disconnectStream()
    connectionState.value = 'connecting'
    emit('connectionStateChange', connectionState.value)

    const credentials = await fetchStreamCredentials(props.deviceId)

    const liveKitRoom = new Room({ adaptiveStream: true })
    liveKitRoom.on(RoomEvent.TrackSubscribed, (track) => {
      if (track.kind === Track.Kind.Video || track.kind === Track.Kind.Audio) {
        const element = track.attach()
        element.classList.add('h-full', 'w-full', 'object-cover')
        videoContainer.value?.appendChild(element)
      }
    })
    liveKitRoom.on(RoomEvent.TrackUnsubscribed, (track) => {
      track.detach().forEach((element) => element.remove())
    })
    liveKitRoom.on(RoomEvent.Connected, () => {
      connectionState.value = 'live'
      emit('connectionStateChange', connectionState.value)
    })
    liveKitRoom.on(RoomEvent.Disconnected, () => {
      connectionState.value = 'idle'
      emit('connectionStateChange', connectionState.value)
    })

    await liveKitRoom.connect(credentials.url, credentials.token)
    room = liveKitRoom
  } catch (error) {
    connectionState.value = 'error'
    emit('connectionStateChange', connectionState.value)
    const message = getErrorMessage(error, 'Unable to connect to the live stream.')
    errorMessage.value = message
    emit('error', message)
    await disconnectStream()
  } finally {
    loadingStream.value = false
  }
}

async function stopStream(): Promise<void> {
  errorMessage.value = null
  await disconnectStream()
}

async function captureFrame(): Promise<void> {
  if (!canCapture.value) {
    return
  }

  capturing.value = true
  errorMessage.value = null
  captureMessage.value = null

  try {
    const response = await captureDeviceFrame(props.deviceId)
    const message = `Frame captured at ${new Date(response.capturedAt).toLocaleTimeString()}.`
    captureMessage.value = message
    emit('captureSuccess', message)
  } catch (error) {
    const message = getErrorMessage(error, 'Unable to capture frame.')
    errorMessage.value = message
    emit('error', message)
  } finally {
    capturing.value = false
  }
}

watch(
  () => props.deviceId,
  async (newId, oldId) => {
    if (newId !== oldId) {
      captureMessage.value = null
      errorMessage.value = null
      await disconnectStream()
    }
  },
)

onUnmounted(() => {
  void disconnectStream()
})
</script>

<template>
  <section class="overflow-hidden rounded-xl border border-white/10 bg-surface-900">
    <div class="relative aspect-video bg-black">
      <div ref="videoContainer" class="absolute inset-0" />
      <div
        v-if="connectionState !== 'live'"
        class="absolute inset-0 flex flex-col items-center justify-center gap-2 px-6 text-center text-gray-400"
      >
        <p class="text-lg font-medium text-gray-300">{{ statusLabel }}</p>
        <p class="text-sm">
          {{
            deviceId
              ? `Press Play to start the stream from ${deviceName ?? 'the selected device'}.`
              : 'Select a device to view the camera feed.'
          }}
        </p>
      </div>
    </div>

    <div class="flex flex-wrap items-center gap-3 border-t border-white/10 px-5 py-4">
      <button
        type="button"
        class="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-emerald-500 disabled:cursor-not-allowed disabled:opacity-50"
        :disabled="!canPlay"
        @click="playStream"
      >
        Play
      </button>
      <button
        type="button"
        class="rounded-lg border border-white/10 bg-surface-800 px-4 py-2 text-sm font-medium text-white transition hover:bg-surface-700 disabled:cursor-not-allowed disabled:opacity-50"
        :disabled="!canStop"
        @click="stopStream"
      >
        Stop
      </button>
      <button
        type="button"
        class="rounded-lg border border-accent-500/40 bg-accent-500/10 px-4 py-2 text-sm font-medium text-accent-300 transition hover:bg-accent-500/20 disabled:cursor-not-allowed disabled:opacity-50"
        :disabled="!canCapture"
        @click="captureFrame"
      >
        {{ capturing ? 'Capturing…' : 'Capture Frame' }}
      </button>

      <span
        class="ml-auto text-sm font-medium"
        :class="{
          'text-green-400': connectionState === 'live',
          'text-yellow-400': connectionState === 'connecting',
          'text-red-400': connectionState === 'error',
          'text-gray-400': connectionState === 'idle',
        }"
      >
        {{ statusLabel }}
      </span>
    </div>

    <p v-if="captureMessage" class="border-t border-white/10 px-5 py-3 text-sm text-emerald-300">
      {{ captureMessage }}
    </p>
    <p v-if="errorMessage" class="border-t border-white/10 px-5 py-3 text-sm text-red-300">
      {{ errorMessage }}
    </p>
  </section>
</template>
