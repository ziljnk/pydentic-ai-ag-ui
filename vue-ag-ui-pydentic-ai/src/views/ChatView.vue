<script setup lang="ts">
import { ref, onMounted, nextTick, watch } from 'vue'
import { useChatStore } from '@/stores/chat'

const chat = useChatStore()
const input = ref('')
const documentState = ref('')
const autoScroll = ref(true)
const listEl = ref<HTMLElement | null>(null)

function send() {
  if (!input.value.trim()) return
  chat.sendMessage(input.value, { stateDocument: documentState.value })
  input.value = ''
  nextTick(scrollToBottom)
}

function scrollToBottom() {
  if (!autoScroll.value || !listEl.value) return
  listEl.value.scrollTop = listEl.value.scrollHeight
}

function formatTime(date = new Date()) {
  return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
}

watch(() => chat.messages.length, () => {
  nextTick(scrollToBottom)
})

onMounted(scrollToBottom)
</script>

<template>
  <div class="chat-container">
    <div class="chat-main">
      <div class="chat-header">
        <div class="user-info">
          <div class="avatar">JJ</div>
          <div class="username">James Johnson</div>
        </div>
        <button class="menu-btn">⋮</button>
      </div>
      
      <div class="messages-wrapper" ref="listEl">
        <div v-if="!chat.messages.length" class="empty">Start the conversation below.</div>
        <div v-for="m in chat.ordered" :key="m.id" class="message-row" :class="m.role">
          <div class="avatar" v-if="m.role === 'user'">JJ</div>
          <div class="message-content">
            <div class="message-bubble" :class="m.role">
              <template v-if="m.error">
                <span class="error">Error: {{ m.error }}</span>
              </template>
              <template v-else>
                <template v-if="m.chunks?.length">
                  <span v-for="(chunk, idx) in m.chunks" :key="idx" class="chunk">
                    {{ chunk }}
                  </span>
                </template>
                <template v-else>
                  <span>{{ m.content }}</span>
                </template>
                <span v-if="m.pending" class="pending">…</span>
              </template>
            </div>
            <div class="message-time">{{ formatTime() }}</div>
          </div>
        </div>
      </div>

      <div class="input-section">
        <form @submit.prevent="send" class="input-form">
          <textarea 
            v-model="input" 
            rows="1"
            placeholder="Type your message"
            @keydown.enter.exact.prevent="send"
            class="message-input"
          />
          <button type="submit" :disabled="!input.trim() || chat.loading" class="send-btn">
            {{ chat.loading ? '⏳' : '➤' }}
          </button>
        </form>
      </div>
    </div>

    <div class="sidebar-panel">
      <h3>Document Context</h3>
      <textarea 
        v-model="documentState" 
        placeholder="Optional document context shared with the agent" 
        rows="12"
        class="context-input"
      />
      <div class="sidebar-actions">
        <button class="secondary-btn" @click="documentState = ''" :disabled="!documentState">
          Clear Document
        </button>
        <button class="secondary-btn" @click="chat.reset()" :disabled="!chat.messages.length">
          Reset Chat
        </button>
      </div>
      <label class="checkbox-label">
        <input type="checkbox" v-model="autoScroll" /> 
        <span>Auto-scroll</span>
      </label>
    </div>
  </div>
</template>

<style scoped>
.chat-container {
  display: flex;
  height: calc(100vh - 56px);
  max-width: 1400px;
  margin: 0 auto;
  gap: 0;
}

.chat-main {
  flex: 1;
  display: flex;
  flex-direction: column;
  background: #fff;
  border-right: 1px solid #e5e7eb;
}

.chat-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 20px;
  border-bottom: 1px solid #e5e7eb;
  background: #fff;
}

.user-info {
  display: flex;
  align-items: center;
  gap: 12px;
}

.avatar {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 14px;
  font-weight: 600;
  flex-shrink: 0;
}

.username {
  font-size: 16px;
  font-weight: 600;
  color: #111827;
}

.menu-btn {
  background: none;
  border: none;
  font-size: 20px;
  cursor: pointer;
  padding: 4px 8px;
  color: #6b7280;
}

.messages-wrapper {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
  background: #f9fafb;
}

.empty {
  text-align: center;
  color: #9ca3af;
  margin-top: 40px;
  font-size: 14px;
}

.message-row {
  display: flex;
  gap: 10px;
  margin-bottom: 20px;
  align-items: flex-start;
}

.message-row.assistant {
  flex-direction: row-reverse;
  text-align: right;
}

.message-row.user .avatar {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
}

.message-content {
  display: flex;
  flex-direction: column;
  gap: 4px;
  max-width: 65%;
}

.message-row.assistant .message-content {
  align-items: flex-end;
}

.message-bubble {
  padding: 12px 16px;
  border-radius: 18px;
  font-size: 15px;
  line-height: 1.5;
  word-wrap: break-word;
  white-space: pre-wrap;
}
.chunk {
  display: inline;
  white-space: pre-wrap;
}

.message-bubble.user {
  background: #dbeafe;
  color: #1e40af;
  border-bottom-left-radius: 4px;
}

.message-bubble.assistant {
  background: #f3f4f6;
  color: #111827;
  border-bottom-right-radius: 4px;
}

.message-time {
  font-size: 11px;
  color: #9ca3af;
  padding: 0 4px;
}

.pending {
  opacity: 0.5;
  animation: pulse 1.5s infinite;
}

@keyframes pulse {
  0%, 100% { opacity: 0.5; }
  50% { opacity: 1; }
}

.error {
  color: #dc2626;
  font-weight: 500;
}

.input-section {
  padding: 16px 20px;
  border-top: 1px solid #e5e7eb;
  background: #fff;
}

.input-form {
  display: flex;
  align-items: flex-end;
  gap: 12px;
  background: #f9fafb;
  border: 1px solid #e5e7eb;
  border-radius: 24px;
  padding: 8px 12px;
}

.message-input {
  flex: 1;
  border: none;
  background: transparent;
  resize: none;
  font-size: 15px;
  line-height: 1.5;
  padding: 6px 8px;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  outline: none;
  max-height: 120px;
}

.send-btn {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  border: none;
  background: #3b82f6;
  color: #fff;
  cursor: pointer;
  font-size: 18px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  transition: background 0.2s;
}

.send-btn:hover:not(:disabled) {
  background: #2563eb;
}

.send-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.sidebar-panel {
  width: 300px;
  background: #fff;
  padding: 20px;
  display: flex;
  flex-direction: column;
  gap: 12px;
  border-left: 1px solid #e5e7eb;
}

.sidebar-panel h3 {
  font-size: 14px;
  font-weight: 600;
  color: #374151;
  margin: 0;
}

.context-input {
  width: 100%;
  padding: 10px;
  border: 1px solid #e5e7eb;
  border-radius: 8px;
  font-size: 13px;
  font-family: 'Courier New', monospace;
  resize: vertical;
  background: #f9fafb;
}

.sidebar-actions {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.secondary-btn {
  padding: 8px 14px;
  border: 1px solid #e5e7eb;
  background: #fff;
  border-radius: 6px;
  font-size: 13px;
  cursor: pointer;
  transition: all 0.2s;
  font-weight: 500;
  color: #374151;
}

.secondary-btn:hover:not(:disabled) {
  background: #f9fafb;
  border-color: #d1d5db;
}

.secondary-btn:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}

.checkbox-label {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 13px;
  color: #6b7280;
  margin-top: 8px;
}

@media (max-width: 900px) {
  .chat-container {
    flex-direction: column-reverse;
  }
  
  .sidebar-panel {
    width: 100%;
    border-left: none;
    border-top: 1px solid #e5e7eb;
  }
  
  .message-content {
    max-width: 80%;
  }
}
</style>
