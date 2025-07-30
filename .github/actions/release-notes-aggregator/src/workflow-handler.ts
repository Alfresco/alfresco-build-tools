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

export class WorkflowHandler {
  private octokit: any
  private releaseNotesExternal: string = '';
  private aggregatedReleaseNotes: string = '';

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

  async generateReleaseNotesFromExternalRepo(): Promise<void> {
    try {
      const releaseNotesExternalResponse = await this.octokit.rest.repos.generateReleaseNotes({
        owner: this.owner,
        repo: this.externalRepo,
        tag_name: this.generateRNtoVersion,
        previous_tag_name: this.generateRNfromVersion,
      });

      this.releaseNotesExternal = releaseNotesExternalResponse.data.body;
      debug('Release Notes External', this.releaseNotesExternal)

    } catch (error: any) {
      debug('External Release Notes in status error', error)
      throw error
    }
  }

  async aggregateExternalReleaseToCurrentReleaseNotes(): Promise<void> {
    try {
      const currentRelease = await this.octokit.rest.repos.getRelease({
          owner: this.owner,
          repo: this.repo,
          release_id: this.releaseId,
      });
      debug('Current Release Notes:', currentRelease.data.body);

      // concatenate the external release to the current by using the repo name as a header
      this.aggregatedReleaseNotes = `${currentRelease.data.body}\n\n---\n\n## ${this.externalRepo}\n\n${this.releaseNotesExternal}`;
    } catch (error: any) {
      debug('Release Notes aggregation in status error', error)
      throw error
    }
  }

  async updateReleaseNotes(): Promise<void> {
    try {
      await this.octokit.rest.repos.updateRelease({
          owner: this.owner,
          repo: this.repo,
          release_id: this.releaseId,
          body: this.aggregatedReleaseNotes,
          draft: false,
          prerelease: false,
      });
    } catch (error: any) {
      debug('Release Notes update in status error', error)
      throw error
    }

    debug(`Conclusion`,`Release notes for the external repo ${this.externalRepo} was aggregated successfully`);

  }

}
