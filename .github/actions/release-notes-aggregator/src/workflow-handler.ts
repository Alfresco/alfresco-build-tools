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
import { debug } from './debug'

export enum WorkflowRunStatus {
  QUEUED = 'queued',
  IN_PROGRESS = 'in_progress',
  COMPLETED = 'completed'
}

const ofStatus = (status: string | null): WorkflowRunStatus => {
  if (!status) {
    return WorkflowRunStatus.QUEUED
  }
  const key = status.toUpperCase() as keyof typeof WorkflowRunStatus
  return WorkflowRunStatus[key]
}

export enum WorkflowRunConclusion {
  SUCCESS = 'success',
  FAILURE = 'failure',
  CANCELLED = 'cancelled',
  SKIPPED = 'skipped',
  NEUTRAL = 'neutral',
  TIMED_OUT = 'timed_out',
  ACTION_REQUIRED = 'action_required'
}

const ofConclusion = (conclusion: string | null): WorkflowRunConclusion => {
  if (!conclusion) {
    return WorkflowRunConclusion.NEUTRAL
  }
  const key = conclusion.toUpperCase() as keyof typeof WorkflowRunConclusion
  return WorkflowRunConclusion[key]
}

export interface WorkflowRunResult {
  id: number,
  url: string,
  status: WorkflowRunStatus,
  conclusion: WorkflowRunConclusion
}


export class WorkflowHandler {
  private octokit: any

  constructor(token: string,
    private owner: string,
    private repo: string,
    private externalRepo: string,
    private generateRNfromVersion: string,
    private generateRNtoVersion: string,
    private releaseId: string) {

    // Get octokit client for making API calls
    this.octokit = github.getOctokit(token)
  }

  async generateReleaseNotesFromExternalRepo(): Promise<string> {
    try {
      const releaseNotesExternalResponse = await this.octokit.rest.repos.generateReleaseNotes({
        owner: this.owner,
        repo: this.externalRepo,
        tag_name: this.generateRNtoVersion,
        previous_tag_name: this.generateRNfromVersion,
      });

      const releaseNotesExternal = releaseNotesExternalResponse.data.body;
      debug('Release Notes External', releaseNotesExternal)

      return releaseNotesExternal;

    } catch (error: any) {
      debug('Workflow Release Notes from external repo status error', error)
      throw error
    }
  }

}
