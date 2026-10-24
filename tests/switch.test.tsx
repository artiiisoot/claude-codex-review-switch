import { expect, test } from 'claude-code/testing'

const ON = '\u00A0\u00A0\u00A0\u00A0●'
const OFF = '●\u00A0\u00A0\u00A0\u00A0'

const BAND = {
  plugin: 'codex-review-switch',
  component: 'AbovePrompt',
  requestId: 'above-prompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 6 },
} as const

test('the switch above the prompt shows the gate and flips it', async ($, on) => {
  let isEnabled = false
  const flags: string[] = []
  on('command.register', () => ({ value: { command: 'codex-review-switch' } }))
  on('ui.close', () => ({ value: undefined }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('store.get', () => ({ value: undefined }))
  on('process.run', (_, e) => {
    const flag = e.argv[4]
    if (flag) flags.push(flag)
    if (flag === '--enable-review-gate') isEnabled = true
    if (flag === '--disable-review-gate') isEnabled = false
    const stdout = JSON.stringify({ ready: true, reviewGateEnabled: isEnabled, auth: { detail: 'ok' } })
    return { value: { exitCode: 0, stdout, stderr: '' } }
  })

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...BAND, surface })
    const before = isEnabled
    // The start-up read runs unawaited; a press settles the work it starts.
    await ui.press({ key: 'refresh' })
    if (surface === 'terminal') expect((await ui.find({ key: 'toggle' }))?.text).toBe(before ? ON : OFF)
    expect(await ui.find({ type: 'Text', text: before ? /^켜짐$/ : /^꺼짐$/ })).toBeDefined()
    await ui.press({ key: 'toggle' })
    if (surface === 'terminal') expect((await ui.find({ key: 'toggle' }))?.text).toBe(before ? OFF : ON)
    expect(await ui.find({ type: 'Text', text: before ? /^꺼짐$/ : /^켜짐$/ })).toBeDefined()
    await ui.unmount()
  }
  expect(flags).toEqual(['--enable-review-gate', '--disable-review-gate'])
})

test('a survey keeps the band to itself', async ($, on) => {
  on('command.register', () => ({ value: { command: 'codex-review-switch' } }))
  on('ui.close', () => ({ value: undefined }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('store.get', () => ({ value: undefined }))
  on('process.run', () => ({ value: { exitCode: 0, stdout: '{"ready":true,"reviewGateEnabled":false}', stderr: '' } }))
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)

    return <Text>survey</Text>
  })
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })

  const ui = await $.ui.mount({ ...BAND, surface: 'desktop', props: { ...BAND.props, hasSurvey: true } })
  expect(await ui.find({ key: 'toggle' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /survey/ })).toBeDefined()
  await ui.unmount()
})
