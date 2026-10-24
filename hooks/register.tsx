import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { CodexReview, GateStatus } from '../types'

// The side pane earlier versions opened; closed on start so it does not linger.
const PANE = 'codex-review-switch'
const gate = atom({ plugin: 'codex-review-switch', key: 'gate' } as const, {
  phase: 'loading',
  isEnabled: false,
  isBusy: false,
  isCodexReady: false,
  detail: '',
} as GateStatus)
const reviews = atom({ plugin: 'codex-review-switch', key: 'reviews' } as const, [] as CodexReview[])
const STORE_KEY = 'reviews'
const MAX_REVIEWS = 200

const CLAUDE_COLOR = '#D97757'
const CODEX_COLOR = '#10A37F'
const SWITCH_ON = '#22C55E'
const SWITCH_OFF = '#9CA3AF'
const SWITCH_BUSY = '#D1D5DB'
const KNOB = '#FFFFFF'
// Non-breaking spaces, so a surface keeps the track's width.
const PAD = '\u00A0\u00A0'
// The empty label of the Button laid over the switch picture, about as wide as the picture.
const HIT_AREA = '\u00A0'.repeat(6)

// A macOS-style switch: a rounded track, green when on, and a white knob with a soft shadow.
function switchSvg(look: 'on' | 'off' | 'busy'): string {
  const track = look === 'on' ? '#34C759' : look === 'busy' ? '#D1D1D6' : '#E5E5EA'
  const knobX = look === 'on' ? 27 : look === 'busy' ? 19 : 11
  return [
    '<svg xmlns="http://www.w3.org/2000/svg" width="38" height="22" viewBox="0 0 38 22">',
    '<defs><filter id="s" x="-50%" y="-50%" width="200%" height="200%">',
    '<feDropShadow dx="0" dy="1" stdDeviation="0.8" flood-color="#000" flood-opacity="0.3"/></filter></defs>',
    `<rect x="0" y="0" width="38" height="22" rx="11" fill="${track}"/>`,
    `<circle cx="${knobX}" cy="11" r="9" fill="#FFFFFF" filter="url(#s)"/>`,
    '</svg>',
  ].join('')
}
const VERDICT = {
  pass: { mark: '✓', color: '#22C55E', label: '지적 사항 없음' },
  block: { mark: '✗', color: '#EF4444', label: '지적 있음' },
  error: { mark: '!', color: '#EAB308', label: '리뷰 실행 실패' },
} as const

// Runs the newest installed codex plugin's setup, with the plugin's own data
// dir so the gate lands in the same state file its Stop hook reads.
const SETUP = [
  'P=$(ls -d "$HOME"/.claude/plugins/cache/openai-codex/codex/*/ 2>/dev/null | sort -V | tail -1)',
  '[ -n "$P" ] || { echo "Codex 플러그인을 찾을 수 없습니다" >&2; exit 1; }',
  'CLAUDE_PLUGIN_DATA="$HOME/.claude/plugins/data/codex-openai-codex" exec node "${P}scripts/codex-companion.mjs" setup --json "$@"',
].join('\n')

// The newest finished job of this Claude session, as the codex plugin recorded it.
const RESULT = [
  'P=$(ls -d "$HOME"/.claude/plugins/cache/openai-codex/codex/*/ 2>/dev/null | sort -V | tail -1)',
  '[ -n "$P" ] || exit 1',
  'CLAUDE_PLUGIN_DATA="$HOME/.claude/plugins/data/codex-openai-codex" exec node "${P}scripts/codex-companion.mjs" result --json',
].join('\n')

function normalize(text: string): string {
  return text.replace(/\s+/g, ' ').trim()
}

// Reads the stop-gate review the codex plugin's Stop hook just ran, if it ran one.
async function recordReview(
  $: EngineInterface,
  e: { session_id: string; cwd: string; last_assistant_message?: string },
  since: string,
  block: string | undefined,
) {
  const { exitCode, stdout } = await $.process.run(['/bin/sh', '-c', RESULT], {
    cwd: e.cwd,
    env: { CODEX_COMPANION_SESSION_ID: e.session_id },
    timeoutMs: 30_000,
  })
  if (exitCode !== 0) return
  const { job, storedJob } = JSON.parse(stdout)
  if (job?.title !== 'Codex Stop Gate Review' || !(job.createdAt >= since)) return

  const raw = String(storedJob?.result?.rawOutput ?? job.summary ?? '').trim()
  const [first = '', ...rest] = raw.split(/\r?\n/)
  const verdict: CodexReview['verdict'] = first.startsWith('ALLOW:')
    ? 'pass'
    : first.startsWith('BLOCK:')
      ? 'block'
      : 'error'
  const review: CodexReview = {
    id: String(job.id),
    verdict,
    summary: verdict === 'error' ? block ?? (first || '결과를 읽을 수 없습니다') : first.replace(/^(ALLOW|BLOCK):\s*/, ''),
    detail: rest.join('\n').trim(),
    replyText: normalize(e.last_assistant_message ?? ''),
    at: new Date().toISOString(),
  }
  const list = await update($, reviews, all => [...all.filter(r => r.id !== review.id), review].slice(-MAX_REVIEWS))
  await $.store.set(STORE_KEY, list)
}

async function refresh($: EngineInterface, flag?: string) {
  await update($, gate, g => ({ ...g, isBusy: true }))
  try {
    const argv = ['/bin/sh', '-c', SETUP, 'sh', ...(flag ? [flag] : [])]
    const { exitCode, stdout, stderr } = await $.process.run(argv, { timeoutMs: 60_000 })
    if (exitCode !== 0) throw new Error(stderr.trim() || `exit ${exitCode}`)
    const report = JSON.parse(stdout)
    await update($, gate, (): GateStatus => ({
      phase: 'ready',
      isEnabled: Boolean(report.reviewGateEnabled),
      isBusy: false,
      isCodexReady: Boolean(report.ready),
      detail: report.ready ? report.auth?.detail ?? '' : (report.nextSteps ?? []).join(' '),
    }))
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error)
    await update($, gate, (g): GateStatus => ({ ...g, phase: 'error', isBusy: false, detail }))
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await $.command.register({
      name: 'codex-review-switch',
      description: 'Codex 리뷰 게이트 상태 다시 읽기',
    })
    const kept = await $.store.get(STORE_KEY)
    if (Array.isArray(kept)) await update($, reviews, () => kept as CodexReview[])
    void $.ui.close({ id: PANE })
    void refresh($)

    return started
  })

  on('classic.Stop', async ($, e, next) => {
    const since = new Date().toISOString()
    const result = await next(e)
    try {
      await recordReview($, e, since, result.block)
    } catch (error) {
      $.ui.log(`codex-review-switch: ${error instanceof Error ? error.message : String(error)}`, { to: 'debug' })
    }

    return result
  })

  on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => {
    const { Box, Text } = $.ui.resolve(e)
    const own = await next(e)
    const text = normalize(e.props.text)
    const all = await read($, reviews)
    const review = text ? [...all].reverse().find(r => r.replyText.endsWith(text)) : undefined
    if (!e.props.isFirstOfReply && !review) return own
    const look = review && VERDICT[review.verdict]

    return (
      <Box flexDirection="column">
        {e.props.isFirstOfReply && (
          <Text bold color={CLAUDE_COLOR}>
            ✻ Claude
          </Text>
        )}
        {own}
        {review && look && (
          <Box flexDirection="column" borderStyle="round" borderColor={CODEX_COLOR} paddingX={1} marginTop={1}>
            <Text>
              <Text bold color={CODEX_COLOR}>
                ◆ Codex
              </Text>{' '}
              <Text bold color={look.color}>
                {look.mark} {look.label}
              </Text>
            </Text>
            {review.summary !== '' && <Text dimColor>{review.summary}</Text>}
            {review.detail !== '' && <Text>{review.detail}</Text>}
          </Box>
        )}
      </Box>
    )
  })

  on('command.run', { command: 'codex-review-switch' }, async $ => {
    await refresh($)
    const g = await read($, gate)
    const text =
      g.phase === 'error'
        ? `Codex 리뷰 상태를 읽지 못했습니다: ${g.detail}`
        : `Codex 리뷰 게이트: ${g.isEnabled ? '켜짐' : '꺼짐'} (현재 프로젝트)`

    return { text }
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)

    const { Box, Text, Button } = $.ui.resolve(e)
    const g = await read($, gate)
    const isOn = g.isEnabled
    const state = g.isBusy ? '처리 중…' : isOn ? '켜짐' : '꺼짐'
    const note =
      g.phase === 'loading'
        ? { color: undefined, text: '상태 확인 중…' }
        : g.phase === 'error'
          ? { color: 'red', text: g.detail }
          : !g.isCodexReady
            ? { color: 'yellow', text: `Codex 미준비: ${g.detail}` }
            : { color: undefined, text: isOn ? '답변마다 리뷰 · 최대 15분' : '/codex:review 로 직접 리뷰' }

    const track = g.isBusy ? SWITCH_BUSY : isOn ? SWITCH_ON : SWITCH_OFF
    const knob = g.isBusy ? `${PAD}●${PAD}` : isOn ? `${PAD}${PAD}●` : `●${PAD}${PAD}`
    // Only the remote surfaces carry Svg; the terminal draws the switch in text.
    let picture = null
    if (e.surface !== 'terminal') {
      const { Svg } = $.ui.resolve(e)
      picture = (
        <Svg source={switchSvg(g.isBusy ? 'busy' : isOn ? 'on' : 'off')} alt={`Codex 리뷰 ${state}`} width={38} height={22} />
      )
    }
    const toggle = () => {
      if (g.isBusy || g.phase !== 'ready') return
      void refresh($, isOn ? '--disable-review-gate' : '--enable-review-gate')
    }

    return (
      <Box flexDirection="row" gap={1} alignItems="center">
        <Text bold color={CODEX_COLOR}>
          ◆ Codex 리뷰
        </Text>
        {/* A pill track with the knob at the right when on, at the left when off. */}
        {e.surface === 'terminal' ? (
          <Button key="toggle" plain onPress={toggle}>
            <Text backgroundColor={track} color={KNOB}>
              {knob}
            </Text>
          </Button>
        ) : (
          // A remote surface draws a Button in its own colors, so the switch is a picture with an
          // empty, chromeless Button laid over it to take the press.
          <Box marginRight={1}>
            {picture}
            <Box position="absolute" top={0} left={0}>
              <Button key="toggle" plain onPress={toggle}>
                {HIT_AREA}
              </Button>
            </Box>
          </Box>
        )}
        <Text bold={isOn} color={isOn && !g.isBusy ? SWITCH_ON : undefined} dimColor={!isOn || g.isBusy}>
          {state}
        </Text>
        <Button key="refresh" label="↻" plain dimColor onPress={() => void refresh($)} />
        <Text dimColor={note.color === undefined} color={note.color}>
          {note.text}
        </Text>
      </Box>
    )
  })
}
