# GitHub Action for Dispatching Workflows

This action triggers another GitHub Actions workflow, using the `workflow_dispatch` event.  
The workflow must be configured for this event type e.g. `on: [workflow_dispatch]`

This allows you to chain workflows, the classic use case is have a CI build workflow, trigger a CD release/deploy workflow when it completes. Allowing you to maintain separate workflows for CI and CD, and pass data between them as required.

For details of the `workflow_dispatch` even see [this blog post introducing this type of trigger](https://github.blog/changelog/2020-07-06-github-actions-manual-triggers-with-workflow_dispatch/)

*Note 1.* The GitHub UI will report flows triggered by this action as "manually triggered" even though they have been run programmatically via another workflow and the API

*Note 2.* If you want to reference the target workflow by ID, you will need to list them with the following REST API call `curl https://api.github.com/repos/{{owner}}/{{repo}}/actions/workflows -H "Authorization: token {{pat-token}}"`

*This action is a fork of `aurelien-baudet/workflow-dispatch` with a better management of run-name option and node20 support.*

## Inputs

### `workflow`

> **Required.** The name or the filename or ID of the workflow to trigger and run.

### `token`

> **Required.** A GitHub access token (PAT) with write access to the repo in question.
>
> **NOTE.** The automatically provided token e.g. `${{ secrets.GITHUB_TOKEN }}` can not be used, GitHub prevents this token from being able to fire the  `workflow_dispatch` and `repository_dispatch` event. [The reasons are explained in the docs](https://docs.github.com/en/actions/reference/events-that-trigger-workflows#triggering-new-workflows-using-a-personal-access-token).  
> The solution is to manually create a PAT and store it as a secret e.g. `${{ secrets.PERSONAL_TOKEN }}`

### `inputs`

> **Optional.** The inputs to pass to the workflow (if any are configured), this must be a JSON encoded string, e.g. `{ "myInput": "foobar" }`.
>
> All values must be strings (even if they are used as booleans or numbers in the triggered workflow). The triggered workflow should use `fromJson` function to get the right type

### `ref`

> **Optional.** The Git reference used with the triggered workflow run. The reference can be a branch, tag, or a commit SHA. If omitted the context ref of the triggering workflow is used. If you want to trigger on pull requests and run the target workflow in the context of the pull request branch, set the ref to `${{ github.event.pull_request.head.ref }}`

### `repo`

> **Optional.** The default behavior is to trigger workflows in the same repo as the triggering workflow, if you wish to trigger in another GitHub repo "externally", then provide the owner + repo name with slash between them e.g. `microsoft/vscode`

### `run-name` (since 3.0.0)

> **Optional.** The default behavior is to get the remote run ID based on the latest workflow name and date, if you have multiple of the same workflow running at the same time it can point to an incorrect run id.
> To prevent from this, you can specify a unique run name to fetch the concerned run ID. It will also requires you to set that same value as an input for your remote workflow (See the [corresponding example](#invoke-workflow-with-a-unique-run-name-since-300))

### `wait-for-completion`

> **Optional.** If `true`, this action will actively poll the workflow run to get the result of the triggered workflow. It is enabled by default. If the triggered workflow fails due to either `failure`, `timed_out` or `cancelled` then the step that has triggered the other workflow will be marked as failed too.

### `wait-for-completion-timeout`

> **Optional.** The time to wait to mark triggered workflow has timed out. The time must be suffixed by the time unit e.g. `10m`. Time unit can be `s` for seconds, `m` for minutes and `h` for hours. It has no effect if `wait-for-completion` is `false`. Default is `1h`

### `wait-for-completion-interval`

> **Optional.** The time to wait between two polls for getting run status. The time must be suffixed by the time unit e.g. `10m`. Time unit can be `s` for seconds, `m` for minutes and `h` for hours. It has no effect if `wait-for-completion` is `false`. Default is `1m`.
>
> **/!\ Do not use a value that is too small to avoid `API Rate limit exceeded`**

### `display-workflow-run-url`

> **Optional.** If `true`, it displays in logs the URL of the triggered workflow. It is useful to follow the progress of the triggered workflow. It is enabled by default.

### `display-workflow-run-url-timeout`

> **Optional.** The time to wait for getting the workflow run URL. If the timeout is reached, it doesn't fail and continues. Displaying the workflow URL is just for information purpose. The time must be suffixed by the time unit e.g. `10m`. Time unit can be `s` for seconds, `m` for minutes and `h` for hours. It has no effect if `display-workflow-run-url` is `false`. Default is `10m`

### `display-workflow-run-url-interval`

> **Optional.** The time to wait between two polls for getting workflow run URL. The time must be suffixed by the time unit e.g. `10m`. Time unit can be `s` for seconds, `m` for minutes and `h` for hours. It has no effect if `display-workflow-run-url` is `false`. Default is `1m`.
>
> **/!\ Do not use a value that is too small to avoid `API Rate limit exceeded`**

### `workflow-logs`

> **Optional.** Indicate what to do with logs of the triggered workflow:
>
> * `print`: Retrieve the logs for each job of the triggered workflow and print into the logs of the job that triggered the workflow.
> * `ignore`: Do not retrieve log of triggered workflow at all (default).
>
> Only available when `wait-for-completion` is `true`.
>
> Default is `ignore`.

## Outputs

### `workflow-id`

> The ID of the worflow run that has been triggered.

### `workflow-url`

> The URL of the workflow run that has been triggered. It may be undefined if the URL couldn't be retrieved (timeout reached) or if `wait-for-completion` and `display-workflow-run-url` are > both `false`

### `workflow-conclusion`

> The result of the triggered workflow. May be one of `success`, `failure`, `cancelled`, `timed_out`, `skipped`, `neutral`, `action_required`. The step in your workflow will fail if the triggered workflow completes with `failure`, `cancelled` or `timed_out`. Other workflow conlusion are considered success.
> Only available if `wait-for-completion` is `true`

### `workflow-logs`

> The logs of the triggered workflow based if `inputs.workflow-logs` is set to either `output`, or `json-output`.  
> Based on the value, result will be:
>
> * `output`: Multiline string
    >
    >   ```log
>   <job-name> | <datetime> <message>
>   <job-name> | <datetime> <message>
>   ...
>   ```
>
> * `json-output`: JSON string
    >
    >   ```json
>   {
>     "<job-name>": [
>       {
>         "datetime": "<datetime>",
>         "message": "<message>"
>       },
>       {
>         "datetime": "<datetime>",
>         "message": "<message>"
>       }
>     ]
>   }
>   ```

## Example usage

### Invoke workflow without inputs. Wait for result

```yaml
- name: Invoke workflow without inputs. Wait for result
  uses: the-actions-org/workflow-dispatch@v4
  with:
    workflow: My Workflow
    token: ${{ secrets.PERSONAL_TOKEN }}
```

### Invoke workflow without inputs. Don't wait for result

```yaml
- name: Invoke workflow without inputs. Don't wait for result
  uses: the-actions-org/workflow-dispatch@v4
  with:
    workflow: My Workflow
    token: ${{ secrets.PERSONAL_TOKEN }}
    wait-for-completion: false
```

### Invoke workflow with inputs

```yaml
- name: Invoke workflow with inputs
  uses: the-actions-org/workflow-dispatch@v4
  with:
    workflow: Another Workflow
    token: ${{ secrets.PERSONAL_TOKEN }}
    inputs: '{ "message": "blah blah", "debug": true }'
```

### Invoke workflow in another repo with inputs

```yaml
- name: Invoke workflow in another repo with inputs
  uses: the-actions-org/workflow-dispatch@v4
  with:
    workflow: Some Workflow
    repo: benc-uk/example
    token: ${{ secrets.PERSONAL_TOKEN }}
    inputs: '{ "message": "blah blah", "debug": true }'
```

### Invoke workflow and handle result

```yaml
- name: Invoke workflow and handle result
  id: trigger-step
  uses: the-actions-org/workflow-dispatch@v4
  with:
    workflow: Another Workflow
    token: ${{ secrets.PERSONAL_TOKEN }}
- name: Another step that can handle the result
  if: always()
  run: echo "Another Workflow conclusion: ${{ steps.trigger-step.outputs.workflow-conclusion }}"
```

### Invoke workflow and scrap output

```yaml
- name: Invoke workflow and scrap output
  id: trigger-step
  uses: the-actions-org/workflow-dispatch@v4
  with:
    workflow: Another Workflow
    token: ${{ secrets.PERSONAL_TOKEN }}
    workflow-logs: json-output
- name: Another step that can handle the result
  if: always()
  run: echo '${{ fromJSON(steps.trigger-step.outputs.workflow-logs).my-remote-job }}'
```

```yaml
name: Another Workflow

on:
  workflow_dispatch:

jobs:
  my-remote-job:
    - run: echo "Hello world!"
```

### Invoke workflow with a unique run name (since 3.0.0)

```yaml
- name: Invoke workflow and handle result
  id: trigger-step
  uses: the-actions-org/workflow-dispatch@v4
  env:
    RUN_NAME: ${{ github.repository }}/actions/runs/${{ github.run_id }}
  with:
    run-name: ${{ env.RUN_NAME }}
    workflow: Another Workflow
    token: ${{ secrets.PERSONAL_TOKEN }}
    inputs: >-
      {
        "run-name": "${{ env.RUN_NAME }}"
      }
```

:warning: In you remote workflow, you will need to forward and use the `run-name` input (See [GitHub Action run-name](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#run-name))

```yaml
name: Another Workflow
run-name: ${{ inputs.run-name }}

on:
  workflow_dispatch:
    inputs:
      run-name:
        description: 'The distinct run name used to retrieve the run ID. Defaults to the workflow name'
        type: string
        required: false
```

## Contributions

Thanks to:

* [LudovicTOURMAN](https://github.com/LudovicTOURMAN )
* [Djontleman](https://github.com/Djontleman)
* [aurelien-baudet](https://github.com/aurelien-baudet)
* [samirergaibi](https://github.com/samirergaibi)
* [rui-ferreira](https://github.com/rui-ferreira)
* [robbertvdg](https://github.com/robbertvdg)
* [samit2040](https://github.com/samit2040)
* [jonas-schievink](https://github.com/jonas-schievink)
