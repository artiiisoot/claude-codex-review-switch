import { expect, test } from 'claude-code/testing'

const REPLY = '수정을 마쳤습니다.\n\n테스트도 통과했습니다.'

function message(text: string, isFirstOfReply: boolean, surface: 'terminal' | 'desktop') {
  return {
    plugin: 'codex-review-switch',
    component: 'AssistantMessage',
    requestId: `m-${isFirstOfReply}`,
    surface,
    props: { text, isFirstOfReply },
  } as const
}

function stubCodex(on: Parameters<Parameters<typeof test>[1]>[1], rawOutput: string) {
  on('command.register', () => ({ value: { command: 'codex-review-switch' } }))
  on('ui.close', () => ({ value: undefined }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('store.get', () => ({ value: undefined }))
  on('store.set', () => ({ value: undefined }))
  on('ui.log', () => ({ value: undefined }))
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)

    return <Text>engine</Text>
  })
  on('process.run', (_, e) => {
    const isResult = String(e.argv[2]).includes('result --json')
    const stdout = isResult
      ? JSON.stringify({
          job: { id: 'task-1', title: 'Codex Stop Gate Review', createdAt: new Date(Date.now() + 1000).toISOString(), summary: rawOutput.split('\n')[0] },
          storedJob: { result: { rawOutput } },
        })
      : JSON.stringify({ ready: true, reviewGateEnabled: true })
    return { value: { exitCode: 0, stdout, stderr: '' } }
  })
}

test('a passed review leaves a Codex row under the reviewed reply', async ($, on) => {
  stubCodex(on, 'ALLOW: no blocking issues')
  on('classic.Stop', () => ({}))
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await $.classic.Stop({ stop_hook_active: false, last_assistant_message: REPLY })

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount(message('테스트도 통과했습니다.', false, surface))
    expect(await ui.find({ type: 'Text', text: /◆ Codex/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /✓ 지적 사항 없음/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /no blocking issues/ })).toBeDefined()
    await ui.unmount()

    const first = await $.ui.mount(message('수정을 마쳤습니다.', true, surface))
    expect(await first.find({ type: 'Text', text: /✻ Claude/ })).toBeDefined()
    expect(await first.find({ type: 'Text', text: /◆ Codex/ })).toBeUndefined()
    await first.unmount()
  }
})

test('a blocking review keeps its block and shows the issue', async ($, on) => {
  stubCodex(on, 'BLOCK: missing null check\nsrc/a.ts:12 reads user.name before the guard')
  const reason = 'Codex stop-time review found issues that still need fixes before ending the session: missing null check'
  on('classic.Stop', () => ({ block: reason }))
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  const result = await $.classic.Stop({ stop_hook_active: false, last_assistant_message: REPLY })
  expect(result.block).toBe(reason)

  const ui = await $.ui.mount(message('테스트도 통과했습니다.', false, 'desktop'))
  expect(await ui.find({ type: 'Text', text: /✗ 지적 있음/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /missing null check/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /src\/a\.ts:12/ })).toBeDefined()
  await ui.unmount()
})

test('no review ran: the reply draws as before, with only the Claude mark', async ($, on) => {
  on('command.register', () => ({ value: { command: 'codex-review-switch' } }))
  on('ui.close', () => ({ value: undefined }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('store.get', () => ({ value: undefined }))
  on('store.set', () => ({ value: undefined }))
  on('ui.log', () => ({ value: undefined }))
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)

    return <Text>engine</Text>
  })
  on('process.run', () => ({ value: { exitCode: 1, stdout: '', stderr: 'No finished Codex jobs' } }))
  on('classic.Stop', () => ({}))
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await $.classic.Stop({ stop_hook_active: false, last_assistant_message: REPLY })

  const ui = await $.ui.mount(message('테스트도 통과했습니다.', false, 'desktop'))
  expect(await ui.find({ type: 'Text', text: /Codex/ })).toBeUndefined()
  await ui.unmount()
})
