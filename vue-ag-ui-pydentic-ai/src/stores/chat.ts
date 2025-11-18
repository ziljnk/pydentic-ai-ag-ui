import { defineStore } from 'pinia'
import { getChatEndpoint, postChat, type ChatPostPayload } from '@/services/api'

export interface ChatMessage {
  id: string
  role: 'user' | 'assistant' | 'system'
  content: string
  error?: string
  pending?: boolean
  chunks?: string[]
}

interface SendOptions {
  stateDocument?: string
}

function uuid() {
  return crypto.randomUUID?.() || Math.random().toString(36).slice(2)
}

export const useChatStore = defineStore('chat', {
  state: () => ({
    messages: [] as ChatMessage[],
    loading: false,
    streaming: false,
    endpoint: getChatEndpoint(),
    threadId: 'thread-' + uuid(),
  }),
  getters: {
    ordered(state) {
      return state.messages
    },
  },
  actions: {
    async sendMessage(text: string, opts: SendOptions = {}) {
      if (!text.trim()) return
      const userMsg: ChatMessage = { id: uuid(), role: 'user', content: text }
      this.messages.push(userMsg)
      const assistantMsg: ChatMessage = {
        id: uuid(),
        role: 'assistant',
        content: '',
        pending: true,
        chunks: [],
      }
      this.messages.push(assistantMsg)
      const assistantMessage = this.messages[this.messages.length - 1]

      const appendChunk = (delta: string) => {
        if (!assistantMessage) return
        assistantMessage.chunks = assistantMessage.chunks || []
        assistantMessage.chunks.push(delta)
        assistantMessage.content = assistantMessage.chunks.join('')
      }

      const setContent = (value: string) => {
        if (!assistantMessage) return
        assistantMessage.content = value
      }

      this.loading = true
      this.streaming = true

      const payload = buildPayload({
        threadId: this.threadId,
        userMessageId: userMsg.id,
        text,
        stateDocument: opts.stateDocument,
      })

      try {
        const { received, raw } = await streamViaFetch({
          endpoint: this.endpoint,
          payload,
          onDelta: appendChunk,
        })

        if (!received) {
          if (raw) {
            const parsed = extractTextFromEvents(raw) || raw
            setContent(parsed)
          } else {
            const res = await postChat(payload)
            const textContent = extractTextFromEvents(res.data)
            setContent(textContent || (typeof res.data === 'string' ? res.data : JSON.stringify(res.data)))
          }
        }
      } catch (streamErr: any) {
        try {
          const res = await postChat(payload)
          const textContent = extractTextFromEvents(res.data)
          setContent(textContent || (typeof res.data === 'string' ? res.data : JSON.stringify(res.data)))
        } catch (err: any) {
          if (assistantMessage) {
            assistantMessage.error = err?.message || streamErr?.message || String(streamErr)
          }
        }
      } finally {
        if (assistantMessage) {
          assistantMessage.pending = false
        }
        this.loading = false
        this.streaming = false
      }
    },
    reset() {
      this.messages = []
    },
  },
})

function buildPayload({
  threadId,
  userMessageId,
  text,
  stateDocument,
}: {
  threadId: string
  userMessageId: string
  text: string
  stateDocument?: string
}): ChatPostPayload {
  return {
    threadId,
    runId: 'run-' + uuid(),
    messages: [
      {
        id: userMessageId,
        role: 'user',
        content: text,
      },
    ],
    state: { document: stateDocument || '' },
    tools: [],
    context: [],
    forwardedProps: {},
  }
}

async function streamViaFetch({
  endpoint,
  payload,
  onDelta,
}: {
  endpoint: string
  payload: ChatPostPayload
  onDelta: (delta: string) => void
}): Promise<{ received: boolean; raw: string }> {
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Accept: 'text/event-stream',
    },
    body: JSON.stringify(payload),
  })
  if (!response.ok) throw new Error(`HTTP ${response.status}`)

  const contentType = response.headers.get('content-type')?.toLowerCase() || ''
  if (!contentType.includes('text/event-stream')) {
    const body = await response.text()
    return { received: false, raw: body }
  }

  const reader = response.body?.getReader()
  if (!reader) throw new Error('No readable stream returned')
  const decoder = new TextDecoder('utf-8')
  let received = false
  const collected: string[] = []
  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    const chunk = decoder.decode(value, { stream: true })
    const lines = chunk.split(/\r?\n/)
    for (const line of lines) {
      const event = parseEventLine(line)
      const delta = extractDelta(event)
      if (delta) {
        received = true
        collected.push(delta)
        onDelta(delta)
      }
    }
  }
  const raw = collected.join('')
  return { received, raw }
}

function parseEventLine(line: string) {
  if (!line) return null
  if (line.startsWith('data:')) {
    line = line.slice(5)
  }
  const trimmed = line.trim()
  if (!trimmed || trimmed === '[DONE]') return null
  try {
    return JSON.parse(trimmed)
  } catch {
    return null
  }
}

function extractDelta(event: any): string {
  if (!event) return ''
  if (typeof event === 'string') return event
  if (event.type === 'TEXT_MESSAGE_CONTENT' && typeof event.delta === 'string') {
    return event.delta
  }
  if (typeof event.delta === 'string') return event.delta
  if (typeof event.content === 'string') return event.content
  return ''
}

function extractTextFromEvents(data: unknown): string {
  if (!data) return ''

  if (typeof data === 'string') {
    const lines = data.split(/\r?\n/)
    let text = ''
    for (const line of lines) {
      const event = parseEventLine(line)
      const delta = extractDelta(event)
      if (delta) text += delta
    }
    return text.trim()
  }

  if (Array.isArray((data as any)?.events)) {
    return (data as any).events
      .map((event: any) => extractDelta(event) || '')
      .join('')
  }

  if (Array.isArray(data)) {
    return (data as any[])
      .map((item) => extractTextFromEvents(item))
      .join('')
  }

  if (typeof data === 'object') {
    const obj = data as Record<string, unknown>
    if (typeof obj.delta === 'string') return obj.delta
    if (typeof obj.content === 'string') return obj.content
    if (typeof obj.output === 'string') return obj.output
    if (typeof obj.output === 'object' && obj.output) {
      return extractTextFromEvents(obj.output)
    }
  }

  return ''
}
