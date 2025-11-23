<script setup lang="ts">
import { ref, onMounted, nextTick, watch } from 'vue'
import { useChatStore } from '@/stores/chat'
import { useFrontendTool } from '@/composables/useFrontendTool'

import CircleTool from '@/components/tools/CircleTool.vue'
import TableTool from '@/components/tools/TableTool.vue'

const chat = useChatStore()
const input = ref('')
const documentState = ref('')
const autoScroll = ref(true)
const listEl = ref<HTMLElement | null>(null)

// Register frontend tools
useFrontendTool(
  'draw_circle',
  'Draw a circle with a specific color',
  {
    type: 'object',
    properties: {
      color: { type: 'string', description: 'The color of the circle' },
    },
    required: ['color'],
  },
  {
    component: CircleTool,
    handler: (args) => {
      console.log(`🎨 Drawing a ${args.color} circle (in-chat)`)
    }
  }
)

useFrontendTool(
  'draw_table',
  'Draw a table with mock data',
  {
    type: 'object',
    properties: {
      rowCount: { type: 'integer', description: 'The number of rows to generate' },
    },
    required: ['rowCount'],
  },
  {
    component: TableTool,
    handler: (args) => {
      console.log(`📊 Generated table with ${args.rowCount} rows`)
    }
  }
)

function send() {
  if (!input.value.trim()) return
  chat.sendMessage(input.value, { 
    stateDocument: documentState.value,
  })
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

// Watch for tool calls to execute frontend tools
watch(() => chat.messages, (messages) => {
  const lastMsg = messages[messages.length - 1]
  if (lastMsg?.role === 'assistant' && lastMsg.toolCalls) {
    for (const tool of lastMsg.toolCalls) {
      if (!tool.isPending && tool.result && !tool.result.includes('Executed')) {
        try {
          let toolName = tool.name
          let args = JSON.parse(tool.args)

          // Handle generic wrapper if used by server
          if (toolName === 'execute_frontend_tool') {
             toolName = args.tool_name
             args = args.args || args // Handle nested args if structured that way
          }

          const registeredTool = chat.registeredTools[toolName]
          if (registeredTool) {
            // Only execute handler if it exists (external tools or hybrid)
            if (registeredTool.handler) {
              registeredTool.handler(args)
            }
            tool.result += ' [Executed on Frontend]'
          }
        } catch (e) {
          console.error('Failed to execute frontend tool', e)
        }
      }
    }
  }
}, { deep: true })

function getToolComponent(toolName: string) {
  return chat.registeredTools[toolName]?.component
}

function parseArgs(argsStr: string) {
  try {
    return JSON.parse(argsStr)
  } catch {
    return {}
  }
}

function resolveToolName(tool: any) {
  if (tool.name === 'execute_frontend_tool') {
    const args = parseArgs(tool.args)
    return args.tool_name || tool.name
  }
  return tool.name
}

function resolveToolArgs(tool: any) {
  const args = parseArgs(tool.args)
  if (tool.name === 'execute_frontend_tool') {
    return args.args || args
  }
  return args
}

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
                <!-- Tool Calls -->
                <div v-if="m.toolCalls?.length" class="tool-calls-container">
                  <div v-for="tool in m.toolCalls" :key="tool.id" class="tool-call">
                    <!-- Render In-Chat Tool Component if available -->
                    <div v-if="getToolComponent(resolveToolName(tool)) && !tool.isPending" class="tool-component-wrapper">
                      <component 
                        :is="getToolComponent(resolveToolName(tool))" 
                        v-bind="resolveToolArgs(tool)" 
                      />
                    </div>

                    <!-- Default Tool UI -->
                    <div v-else class="tool-default-ui">
                      <div class="tool-header">
                        <span class="tool-name">🛠️ {{ tool.name }}</span>
                        <span v-if="tool.isPending" class="tool-status pending">Running...</span>
                        <span v-else class="tool-status done">Done</span>
                      </div>
                      <div class="tool-args" v-if="tool.args">
                        <div class="label">Args:</div>
                        <pre>{{ tool.args }}</pre>
                      </div>
                      <div class="tool-result" v-if="tool.result">
                        <div class="label">Result:</div>
                        <pre>{{ tool.result }}</pre>
                      </div>
                    </div>
                  </div>
                </div>

                <!-- Text Content -->
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

.tool-calls-container {
  display: flex;
  flex-direction: column;
  gap: 8px;
  margin-bottom: 8px;
  width: 100%;
}

.tool-call {
  background: #fff;
  border: 1px solid #e5e7eb;
  border-radius: 8px;
  overflow: hidden;
  font-size: 13px;
  box-shadow: 0 1px 2px rgba(0,0,0,0.05);
}

.tool-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 6px 10px;
  background: #f9fafb;
  border-bottom: 1px solid #e5e7eb;
}

.tool-name {
  font-weight: 600;
  color: #374151;
  font-family: monospace;
}

.tool-status {
  font-size: 10px;
  padding: 2px 6px;
  border-radius: 4px;
  text-transform: uppercase;
  font-weight: 700;
  letter-spacing: 0.05em;
}

.tool-status.pending {
  background: #e0f2fe;
  color: #0369a1;
}

.tool-status.done {
  background: #dcfce7;
  color: #15803d;
}

.tool-args, .tool-result {
  padding: 8px 10px;
  border-bottom: 1px solid #f3f4f6;
}

.tool-result {
  border-bottom: none;
  background: #fdfdfd;
}

.tool-args .label, .tool-result .label {
  font-size: 11px;
  font-weight: 600;
  color: #6b7280;
  margin-bottom: 4px;
  text-transform: uppercase;
}

.tool-args pre, .tool-result pre {
  margin: 0;
  white-space: pre-wrap;
  word-wrap: break-word;
  font-family: 'Menlo', 'Monaco', 'Courier New', monospace;
  color: #4b5563;
  font-size: 12px;
  line-height: 1.4;
}
</style>
