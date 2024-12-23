
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
  private workflowId?: number | string
  private workflowRunId?: number
  private triggerDate = 0

  constructor(token: string,
    private workflowRef: string,
    private owner: string,
    private repo: string,
    private ref: string,
    private runName: string,
    private runId: string) {
    if (runId) {
      this.workflowRunId = parseInt(runId)
    }
    // Get octokit client for making API calls
    this.octokit = github.getOctokit(token)
  }

  async triggerWorkflow(inputs: any) {
    try {
      const workflowId = await this.getWorkflowId()
      this.triggerDate = new Date().setMilliseconds(0)
      const dispatchResp = await this.octokit.rest.actions.createWorkflowDispatch({
        owner: this.owner,
        repo: this.repo,
        workflow_id: workflowId,
        ref: this.ref,
        inputs
      })
      debug('Workflow Dispatch', dispatchResp)
    } catch (error: any) {
      debug('Workflow Dispatch error', error.message)
      throw error
    }
  }

  async rerunFailedJobs(): Promise<string> {
    try {
      const runId = await this.getWorkflowRunId()
      const response = await this.octokit.rest.actions.reRunWorkflowFailedJobs({
        owner: this.owner,
        repo: this.repo,
        run_id: runId
      })

      debug('Restarting failed jobs', response)

      return response.status

    } catch (error: any) {
      debug('Workflow Re-run status error', error)
      throw error
    }
  }

  async getWorkflowRunStatus(): Promise<WorkflowRunResult> {
    try {
      const runId = await this.getWorkflowRunId()
      const response = await this.octokit.rest.actions.getWorkflowRun({
        owner: this.owner,
        repo: this.repo,
        run_id: runId
      })
      debug('Workflow Run status', response)

      return {
        id: runId,
        url: response.data.html_url,
        status: ofStatus(response.data.status),
        conclusion: ofConclusion(response.data.conclusion)
      }

    } catch (error: any) {
      debug('Workflow Run status error', error)
      throw error
    }
  }


  async getWorkflowRunArtifacts(): Promise<WorkflowRunResult> {
    try {
      const runId = await this.getWorkflowRunId()
      const response = await this.octokit.rest.actions.getWorkflowRunArtifacts({
        owner: this.owner,
        repo: this.repo,
        run_id: runId
      })
      debug('Workflow Run artifacts', response)

      return {
        id: runId,
        url: response.data.html_url,
        status: ofStatus(response.data.status),
        conclusion: ofConclusion(response.data.conclusion)
      }

    } catch (error) {
      debug('Workflow Run artifacts error', error)
      throw error
    }
  }

  private async findAllWorkflowRuns() {
    try {
      const workflowId = await this.getWorkflowId()
      const response = await this.octokit.rest.actions.listWorkflowRuns({
        owner: this.owner,
        repo: this.repo,
        workflow_id: workflowId,
        event: 'workflow_dispatch',
        created: `>=${new Date(this.triggerDate).toISOString()}`
      })

      debug('List Workflow Runs', response)

      return response.data.workflow_runs
    } catch (error) {
      debug('Fin all workflow runs error', error)
      throw new Error(`Failed to list workflow runs. Cause: ${error}`)
    }
  }

  async getWorkflowRunId(): Promise<number> {
    if (this.workflowRunId) {
      return this.workflowRunId
    }
    try {
      let runs = await this.findAllWorkflowRuns()
      if (this.runName) {
        runs = runs.filter((r: any) => r.name == this.runName)
      }

      if (runs.length == 0) {
        throw new Error('Run not found')
      }

      if (runs.length > 1) {
        core.warning(`Found ${runs.length} runs. Using the last one.`)
        await this.debugFoundWorkflowRuns(runs)
      }

      this.workflowRunId = runs[0].id as number

      return this.workflowRunId
    } catch (error) {
      debug('Get workflow run id error', error)
      throw error
    }
  }

  private async getWorkflowId(): Promise<number | string> {
    if (this.workflowId) {
      return this.workflowId
    }
    if (this.isFilename(this.workflowRef)) {
      this.workflowId = this.workflowRef
      core.debug(`Workflow id is: ${this.workflowRef}`)
      return this.workflowId
    }
    try {
      const workflowsResp = await this.octokit.rest.actions.listRepoWorkflows({
        owner: this.owner,
        repo: this.repo
      })
      const workflows = workflowsResp.data.workflows
      debug('List Workflows', workflows)

      // Locate workflow either by name or id
      const workflowFind = workflows.find((workflow: any) => workflow.name === this.workflowRef || workflow.id.toString() === this.workflowRef)
      if(!workflowFind) throw new Error(`Unable to find workflow '${this.workflowRef}' in ${this.owner}/${this.repo} 😥`)
      core.debug(`Workflow id is: ${workflowFind.id}`)
      this.workflowId = workflowFind.id as number
      return this.workflowId
    } catch(error) {
      debug('List workflows error', error)
      throw error
    }
  }

  private isFilename(workflowRef: string) {
    return /.+\.ya?ml$/.test(workflowRef)
  }

  private debugFoundWorkflowRuns(runs: any){
    debug(`Filtered Workflow Runs (after trigger date: ${new Date(this.triggerDate).toISOString()})`, runs.map((r: any) => ({
      id: r.id,
      name: r.name,
      created_at: r.created_at,
      triggerDate: new Date(this.triggerDate).toISOString(),
      created_at_ts: new Date(r.created_at).valueOf(),
      triggerDateTs: this.triggerDate
    })))
  }

}

