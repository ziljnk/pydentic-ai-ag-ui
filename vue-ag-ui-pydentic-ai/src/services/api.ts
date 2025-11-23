import axios from 'axios'

// Configure a single axios instance for the app
// Prefer a base endpoint from env: VITE_CHAT_ENDPOINT (full URL including path)
const CHAT_ENDPOINT = (import.meta.env.VITE_CHAT_ENDPOINT as string) || 'http://localhost:8000/ag-ui'

export const apiClient = axios.create({
  // Note: We keep full URL usage in requests to allow swapping endpoints easily
  headers: {
    'Content-Type': 'application/json',
    // We prefer JSON response; backend may still stream SSE if not supported.
    Accept: 'application/json',
  },
  // You can enable withCredentials if your API needs cookies
  withCredentials: false,
  // timeout can be tuned for long responses
  timeout: 120_000,
})

export function getChatEndpoint() {
  return CHAT_ENDPOINT
}

export interface ChatPostPayload {
  threadId: string
  runId: string
  messages: Array<{
    id: string
    role: 'user' | 'assistant' | 'system'
    content: string
  }>
  state?: { 
    document?: string
    frontend_tools?: any[]
  }
  tools?: any[]
  context?: any[]
  forwardedProps?: Record<string, unknown>
}

export async function postChat(payload: ChatPostPayload) {
  const url = CHAT_ENDPOINT
  return apiClient.post(url, payload)
}
