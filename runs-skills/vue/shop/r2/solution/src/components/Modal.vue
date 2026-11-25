<script setup>
import { onMounted, onUnmounted } from 'vue'

const emit = defineEmits(['close'])

function onKeydown(event) {
  if (event.key === 'Escape') emit('close')
}

onMounted(() => window.addEventListener('keydown', onKeydown))
onUnmounted(() => window.removeEventListener('keydown', onKeydown))
</script>

<template>
  <div role="dialog" aria-modal="true">
    <button type="button" @click="emit('close')">Close</button>
    <slot />
  </div>
</template>
