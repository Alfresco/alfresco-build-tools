import { afterEach, beforeEach, describe, it } from 'vitest'
import assert from 'node:assert/strict'
import { formatDuration, getArgs, isTimedOut } from './utils'

const defaults: Record<string, string> = {
  'INPUT_TOKEN': 'secret',
  'INPUT_WORKFLOW': 'build.yml',
  'INPUT_REF': 'main',
  'INPUT_REPO': 'some-owner/some-repo',
  'INPUT_INPUTS': '{"foo":"bar"}',
  'INPUT_DISPLAY-WORKFLOW-RUN-URL': 'true',
  'INPUT_DISPLAY-WORKFLOW-RUN-URL-INTERVAL': '1m',
  'INPUT_DISPLAY-WORKFLOW-RUN-URL-TIMEOUT': '10m',
  'INPUT_WAIT-FOR-COMPLETION': 'false',
  'INPUT_WAIT-FOR-COMPLETION-TIMEOUT': '1h',
  'INPUT_WAIT-FOR-COMPLETION-INTERVAL': '30s',
}

describe('getArgs', () => {
  beforeEach(() => Object.assign(process.env, defaults))
  afterEach(() => Object.keys(defaults).forEach(key => delete process.env[key]))

  it('parses inputs', () => {
    const args = getArgs()
    assert.equal(args.token, 'secret')
    assert.equal(args.workflowRef, 'build.yml')
    assert.equal(args.ref, 'main')
    assert.equal(args.owner, 'some-owner')
    assert.equal(args.repo, 'some-repo')
    assert.deepEqual(args.inputs, { foo: 'bar' })
    assert.equal(args.displayWorkflowUrl, true)
    assert.equal(args.displayWorkflowUrlInterval, 60 * 1000)
    assert.equal(args.displayWorkflowUrlTimeout, 10 * 60 * 1000)
    assert.equal(args.waitForCompletion, false)
    assert.equal(args.waitForCompletionTimeout, 60 * 60 * 1000)
    assert.equal(args.checkStatusInterval, 30 * 1000)
  })

  it('rejects invalid inputs JSON', () => {
    process.env['INPUT_INPUTS'] = '{not json'
    assert.throws(() => getArgs(), /Failed to parse 'inputs' parameter/)
  })

  it('rejects an unknown time unit', () => {
    process.env['INPUT_WAIT-FOR-COMPLETION-TIMEOUT'] = '10x'
    assert.throws(() => getArgs(), /Unknown time unit x/)
  })
})

describe('formatDuration', () => {
  it('formats hours, minutes and seconds', () => {
    assert.equal(formatDuration(3723000), '01h 02m 03s')
  })
})

describe('isTimedOut', () => {
  it('is true once the timeout has elapsed', () => {
    assert.equal(isTimedOut(Date.now() - 2000, 1000), true)
  })

  it('is false before the timeout', () => {
    assert.equal(isTimedOut(Date.now(), 60 * 1000), false)
  })
})
