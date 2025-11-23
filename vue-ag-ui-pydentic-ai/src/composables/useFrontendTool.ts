import { onMounted, onUnmounted, type Component } from 'vue'
import { useChatStore } from '@/stores/chat'

export interface FrontendToolDef {
  name: string
  description: string
  parameters: any
  handler?: (args: any) => void | Promise<void>
  component?: Component
}

export function useFrontendTool(
  name: string, 
  description: string, 
  parameters: any, 
  handlerOrOptions: ((args: any) => void | Promise<void>) | { handler?: (args: any) => void | Promise<void>, component?: Component }
) {
  const store = useChatStore()
  
  let handler: ((args: any) => void | Promise<void>) | undefined
  let component: Component | undefined

  if (typeof handlerOrOptions === 'function') {
    handler = handlerOrOptions
  } else {
    handler = handlerOrOptions.handler
    component = handlerOrOptions.component
  }
  
  const toolDef: FrontendToolDef = {
    name,
    description,
    parameters,
    handler,
    component
  }

  onMounted(() => {
    store.registerTool(name, toolDef)
  })

  onUnmounted(() => {
    store.unregisterTool(name)
  })
}
