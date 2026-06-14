<script setup lang="ts">
import NavSidebar from '@/components/NavSidebar.vue'

defineProps<{
  title: string
  subtitle?: string
}>()
</script>

<template>
  <div class="flex min-h-screen bg-surface-950">
    <NavSidebar />

    <div class="flex min-w-0 flex-1 flex-col">
      <header class="border-b border-white/10 bg-surface-900/80 px-8 py-6 backdrop-blur">
        <h1 class="text-2xl font-semibold text-white">{{ title }}</h1>
        <p v-if="subtitle" class="mt-1 text-sm text-gray-400">{{ subtitle }}</p>
      </header>

      <main class="flex-1 overflow-auto px-8 py-6">
        <slot />
      </main>
    </div>
  </div>
</template>
