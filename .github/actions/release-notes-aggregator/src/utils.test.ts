import { afterEach, beforeEach, describe, it } from 'vitest'
import assert from 'node:assert/strict'

const defaults: Record<string, string> = {
  'GITHUB_REPOSITORY': 'some-owner/some-repo',
  'INPUT_TOKEN': 'secret',
  'INPUT_EXTERNAL-REPO': 'external-repo',
  'INPUT_FROM-EXTERNAL-VERSION': 'v1.0.0',
  'INPUT_TO-EXTERNAL-VERSION': 'v1.1.0',
  'INPUT_RELEASE-ID': '42',
}

describe('getArgs', () => {
  beforeEach(() => Object.assign(process.env, defaults))
  afterEach(() => Object.keys(defaults).concat('INPUT_INPUTS').forEach(key => delete process.env[key]))

  // github.context is built on import, so load utils after GITHUB_REPOSITORY is set
  const loadGetArgs = async () => (await import('./utils')).getArgs

  it('parses inputs', async () => {
    const args = (await loadGetArgs())()
    assert.equal(args.token, 'secret')
    assert.equal(args.owner, 'some-owner')
    assert.equal(args.repo, 'some-repo')
    assert.equal(args.externalRepo, 'external-repo')
    assert.equal(args.generateRNfromVersion, 'v1.0.0')
    assert.equal(args.generateRNtoVersion, 'v1.1.0')
    assert.equal(args.releaseId, '42')
    assert.deepEqual(args.inputs, {})
  })

  it('rejects invalid inputs JSON', async () => {
    process.env['INPUT_INPUTS'] = '{not json'
    const getArgs = await loadGetArgs()
    assert.throws(() => getArgs(), /Failed to parse 'inputs' parameter/)
  })
})
