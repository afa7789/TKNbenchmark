<script setup>
const { name } = defineProps({ name: { type: String, required: true } })
</script>

<template>
  <p>Hello, {{ name }}!</p>
</template>
