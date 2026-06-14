<script setup lang="ts">
defineProps<{
  title?: string
  message: string
}>()
</script>

<template>
  <div
    class="rounded-lg border border-red-500/30 bg-red-500/10 px-4 py-3 text-sm text-red-200"
    role="alert"
  >
    <p v-if="title" class="mb-1 font-semibold text-red-100">{{ title }}</p>
    <p>{{ message }}</p>
  </div>
</template>
