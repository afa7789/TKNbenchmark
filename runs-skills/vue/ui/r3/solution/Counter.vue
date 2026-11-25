<script setup>
import { ref } from 'vue'

const count = ref(0)
</script>

<template>
  <div>
    <span>{{ count }}</span>
    <button type="button" @click="count++">Increment</button>
  </div>
</template>
