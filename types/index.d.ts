export type GateStatus = {
  phase: 'loading' | 'ready' | 'error'
  isEnabled: boolean
  isBusy: boolean
  isCodexReady: boolean
  detail: string
}

// One stop-gate review, tied to the Claude reply it reviewed by that reply's text.
export type CodexReview = {
  id: string
  verdict: 'pass' | 'block' | 'error'
  summary: string
  detail: string
  replyText: string
  at: string
}

declare module 'claude-code' {
  interface PluginState {
    'codex-review-switch': { gate: GateStatus; reviews: CodexReview[] }
  }
}
