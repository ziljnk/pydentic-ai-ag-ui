<script setup lang="ts">
defineProps<{
  color: string
}>()
</script>

<template>
  <div class="circle-tool">
    <div 
      class="circle" 
      :style="{ backgroundColor: color }"
    ></div>
    <span class="caption">Generated {{ color }} circle</span>
  </div>
</template>

<style scoped>
.circle-tool {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
  padding: 12px;
  border: 1px solid #e5e7eb;
  border-radius: 8px;
  background: #fff;
  width: fit-content;
}

.circle {
  width: 100px;
  height: 100px;
  border-radius: 50%;
  box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
}

.caption {
  font-size: 12px;
  color: #6b7280;
}
</style>
