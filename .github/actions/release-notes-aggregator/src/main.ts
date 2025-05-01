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
import { getArgs } from './utils'
import { WorkflowHandler } from './workflow-handler'

async function run(): Promise<void> {
  try {
    const args = getArgs()
    const workflowHandler = new WorkflowHandler(args.token, args.owner, args.repo, args.externalRepo, args.generateRNfromVersion, args.generateRNtoVersion, args.releaseId)

    try {
      await workflowHandler.generateReleaseNotesFromExternalRepo();

      await workflowHandler.aggregateExternalReleaseToCurrentReleaseNotes();

      await workflowHandler.updateReleaseNotes();
    } catch(e: any) {
      core.warning(`Failed to generate the external release note: ${e.message}`);
    }

  } catch (error: any) {
    core.setFailed(error.message)
  }
}

run()
