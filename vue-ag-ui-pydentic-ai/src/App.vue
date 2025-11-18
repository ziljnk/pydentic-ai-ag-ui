<script setup lang="ts">
import { RouterView } from 'vue-router'
</script>

<template>
  <div class="layout">
    <header class="topbar">
      <div class="brand">AG-UI Chat</div>
    </header>
    <main class="content">
      <RouterView />
    </main>
  </div>
  
</template>

<style scoped>
.layout { height: calc(100vh - 4rem); display: flex; flex-direction: column; width: calc(100vw - 4rem); }
.topbar {
  height: 56px;
  display: flex;
  align-items: center;
  padding: 0 16px;
  border-bottom: 1px solid var(--color-border);
  background: var(--color-background-soft, #0b0b0b0a);
  backdrop-filter: blur(6px);
}
.brand { font-weight: 600; letter-spacing: 0.2px; }
.content { flex: 1; }
</style>
