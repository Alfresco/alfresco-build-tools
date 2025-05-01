/*!
 * @license
 * Copyright © 2005-2023 Hyland Software, Inc. and its affiliates. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import * as core from '@actions/core'
import * as github from '@actions/github'

function parse(inputsJson: string) {
  if(inputsJson) {
    try {
      return JSON.parse(inputsJson)
    } catch(e) {
      throw new Error(`Failed to parse 'inputs' parameter. Must be a valid JSON.\nCause: ${e}`)
    }
  }
  return {}
}
export function getArgs() {
  // Required inputs
  const token = core.getInput('token')
  const workflowRef = core.getInput('workflow')
  // Optional inputs, with defaults
  const ref = core.getInput('ref')   || github.context.ref
  const [owner, repo] = [github.context.repo.owner, github.context.repo.repo]

  // Decode inputs, this MUST be a valid JSON string
  const inputs = parse(core.getInput('inputs'))
  const externalRepo = core.getInput('externalRepo')
  const generateRNfromVersion = core.getInput('generateRNfromVersion')
  const generateRNtoVersion = core.getInput('generateRNtoVersion')
  const releaseId = core.getInput('releaseId')

  return {
    token,
    owner,
    repo,
    inputs,
    externalRepo,
    generateRNfromVersion,
    generateRNtoVersion,
    releaseId,
  }
}
