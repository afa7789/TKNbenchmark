<script setup>
import { ref } from 'vue'
const n = ref(0)
</script>
<template><div><span>{{ n }}</span><button @click="n++">Increment</button></div></template>
