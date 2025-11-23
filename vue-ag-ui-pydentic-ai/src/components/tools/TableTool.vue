<script setup lang="ts">
import { computed } from 'vue'

const props = defineProps<{
  rowCount: number
}>()

const rows = computed(() => {
  return Array.from({ length: props.rowCount }, (_, i) => ({
    id: i + 1,
    name: `Item ${i + 1}`,
    price: Math.floor(Math.random() * 100) + 10,
    status: Math.random() > 0.5 ? 'Available' : 'Out of Stock'
  }))
})
</script>

<template>
  <div class="table-tool">
    <div class="table-header">
      <span>Generated Table ({{ rowCount }} rows)</span>
    </div>
    <div class="table-wrapper">
      <table>
        <thead>
          <tr>
            <th>ID</th>
            <th>Name</th>
            <th>Price</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="row in rows" :key="row.id">
            <td>{{ row.id }}</td>
            <td>{{ row.name }}</td>
            <td>${{ row.price }}</td>
            <td>
              <span 
                class="status-badge" 
                :class="row.status === 'Available' ? 'available' : 'out'"
              >
                {{ row.status }}
              </span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<style scoped>
.table-tool {
  border: 1px solid #e5e7eb;
  border-radius: 8px;
  background: #fff;
  overflow: hidden;
  width: 100%;
  max-width: 500px;
  margin-top: 8px;
}

.table-header {
  padding: 8px 12px;
  background: #f9fafb;
  border-bottom: 1px solid #e5e7eb;
  font-size: 12px;
  font-weight: 600;
  color: #6b7280;
  text-transform: uppercase;
}

.table-wrapper {
  overflow-x: auto;
}

table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
}

th, td {
  padding: 8px 12px;
  text-align: left;
  border-bottom: 1px solid #f3f4f6;
}

th {
  background: #fff;
  font-weight: 600;
  color: #374151;
}

tr:last-child td {
  border-bottom: none;
}

.status-badge {
  padding: 2px 6px;
  border-radius: 4px;
  font-size: 11px;
  font-weight: 500;
}

.status-badge.available {
  background: #dcfce7;
  color: #15803d;
}

.status-badge.out {
  background: #fee2e2;
  color: #b91c1c;
}
</style>
