---
title: Workflow run auto-retry
---

# Workflow run auto-retry

Re-runs the failed jobs of a completed workflow run when every failure is
retryable, and reports when it is not.

## Problem

A long chain of dependent workflows, where each one triggers the next, stops
entirely when a single flaky job fails anywhere along it. Someone has to
notice and press "Re-run failed jobs" by hand, and the longer that takes the
more work piles up behind it.

Re-running everything automatically is not safe either. A release workflow
publishes artifacts, pushes tags and updates downstream repositories, and
repeating any of those turns a flaky test into a real problem.

## Shape

The action is a decision, not a notification. A watcher workflow in the
repository being watched listens for the run completing, calls the action, and
decides for itself what to do with the answer.

```yaml
name: Auto-retry

on:
  workflow_run:
    workflows: ["Release"]
    types: [completed]
    branches: [master, "release/**"]

permissions:
  actions: write
  contents: read

jobs:
  retry:
    # Evaluated before a runner is allocated, so a successful run costs nothing.
    if: contains(fromJSON('["failure","timed_out"]'), github.event.workflow_run.conclusion)
    runs-on: ubuntu-latest
    steps:
      - id: retry
        uses: Alfresco/alfresco-build-tools/.github/actions/workflow-run-auto-retry@v19.5.0
```

Both permissions are required. `actions: write` re-runs the jobs, and
`contents: read` reads the configuration file and the branch tip. Naming any
permission sets every unnamed one to `none`, so leaving `contents` out makes
the action behave as though the repository were not configured at all.

## Configuration

The watched repository holds its own configuration at
`.github/workflow-run-auto-retry.yml`, on its default branch:

```yaml
# Behaviour of the auto-retry workflow. Removing this file turns the retry off.
max-attempts: 3
non-retryable-jobs:
  - "Push to Nexus"
  - "Update downstream repository"
```

| Key | Required | Meaning |
| --- | --- | --- |
| `max-attempts` | no, defaults to 3 | Total attempts allowed, so 3 means the first run plus 2 retries |
| `non-retryable-jobs` | yes | Job display names that must never be re-run automatically |

`max-attempts` counts attempts, not retries. The action compares it against
`run_attempt`, which starts at 1 for the original run.

The file lives in the watched repository so the people reading that repository
can see the rules that apply to it, and change them in a reviewed pull request.

### Turning it off

Either delete the configuration file, or disable the watcher workflow with
`gh workflow disable`. The second needs no pull request, which matters when a
release is already going wrong.

### Alternatives considered

Repository variables were the first design for both the configuration and an
on/off switch. They were rejected because variables are not visible to
everyone who can read a repository, and a setting that silently decides
whether a release retries should be as reviewable as the workflow it controls.

An `enabled:` key in the configuration file was also dropped. Disabling the
workflow already does the job, and a second switch is one more thing to keep
in sync.

## Decision sequence

The action returns `retry`, `escalate` or `none`, in this order:

1. **No configuration file on the default branch** — `none`. The action is
   inert until a repository opts in.
2. **No job reported a failure** — `escalate`. The run failed without a failed
   job, so re-running changes nothing and a human needs to look.
3. **A non-retryable job failed** — `escalate`. Checked before the branch
   check, so a partially completed release always reports rather than going
   quiet.
4. **The branch has moved on** — `none`. A re-run replays the original commit,
   not the branch tip, so a newer run has already superseded this one.
5. **The attempt budget is spent** — `escalate`.
6. Otherwise — `retry`.

Every outcome is written to the job summary, so a run that decided not to
retry still says why.

Any API error other than a 404 fails the step. A 404 means "not there", which
is a real answer; anything else is unknown, and treating it as "do nothing"
would hide exactly the stall this action exists to prevent.

### Matching job names

Job names are matched whole, never as a substring. A reusable workflow called
from another workflow has its job names prefixed, so a job named
`run_ci / Push to Nexus` is a different job from `Push to Nexus` and is
retried normally.

Use the display name as the API reports it, which is the `name:` of the job
when it has one and the YAML key when it does not. A matrix job that never
started reports its name expression unexpanded.

A job that was gated and did not run reports `skipped`, not `failure`, so it
never blocks a retry.

## Inputs

| Input | Required | Default | Meaning |
| --- | --- | --- | --- |
| `config-path` | no | `.github/workflow-run-auto-retry.yml` | Configuration file to read from the default branch |
| `github-token` | no | `${{ github.token }}` | Needs `actions: write` and `contents: read` |

## Outputs

| Output | Meaning |
| --- | --- |
| `decision` | `retry`, `escalate` or `none` |
| `reason` | One sentence explaining the decision, suitable for a notification body |
| `failed-jobs` | Newline-separated display names of the jobs that failed on this attempt |
| `attempt` | The attempt number that just failed |
| `max-attempts` | The configured attempt budget |

## Escalation

The action does not notify anyone. It reports a decision and leaves the
routing to the caller, so a repository can send escalations wherever it
already sends alerts.

A caller that has no notification channel yet can fail the watcher job
instead, which keeps the escalation visible in the Actions tab:

```yaml
      - name: Report
        if: steps.retry.outputs.decision == 'escalate'
        env:
          REASON: ${{ steps.retry.outputs.reason }}
          RUN_URL: ${{ github.event.workflow_run.html_url }}
        run: |
          echo "::error::$REASON"
          echo "Run: $RUN_URL"
          exit 1
```

When sending to Teams, pass `status: failure` explicitly.
`send-teams-notification` otherwise works the status out from the watcher's
own jobs, which have not failed, and the card arrives green.

## Evidence

The following GitHub behaviour was confirmed on a scratch repository rather
than assumed:

| Question | Result |
| --- | --- |
| Does a watcher on the default branch fire for a run on another branch? | Yes |
| Does an explicit `permissions:` block survive a read-only repository default? | Yes |
| Can `GITHUB_TOKEN` re-run failed jobs? | Yes |
| Does a `GITHUB_TOKEN`-initiated re-run fire a fresh `workflow_run` event? | Yes |
| Does the attempt budget stop the cascade? | Yes, no run after the budget |

The fourth answer is what makes the budget necessary: each retry is watched
the same way the original run was, so the action has to stop itself.

## Known limitations

- **The whole run is re-run from the failed jobs, not a single job.**
  `gh run rerun --failed` has no per-job form, so one flaky job re-runs every
  failed job in that attempt.
- **Per-job attempt limits are not supported.** A `job-attempts` map was
  considered and deferred; `max-attempts` applies to the run.
- **The watcher only fires on the default branch.** This is a `workflow_run`
  restriction, not a choice. The watcher must be merged to the default branch
  before it does anything, including on release branches.
- **A re-run replays the original commit.** This is why the branch tip is
  checked, and why a moved branch stops the retry.
- **Teams cards describe the watcher run.** The run link, branch and commit on
  the card come from the watcher, not the failed run. Pass the failed run's
  URL as a card action to make it reachable.
