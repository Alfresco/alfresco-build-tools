---
title: Release chain auto-retry
---

Design for `release-chain-auto-retry` (ACS-13087), the shared action behind the automated release
chain retry work in ACS-13044.

- [Problem](#problem)
- [Shape](#shape)
- [Configuration](#configuration)
  - [Turning it off](#turning-it-off)
  - [Alternatives considered](#alternatives-considered)
- [Decision sequence](#decision-sequence)
- [Action inputs](#action-inputs)
- [Escalation](#escalation)
- [Collected per-repository values](#collected-per-repository-values)
- [Evidence](#evidence)
- [Known limitations](#known-limitations)

## Problem

The ACS release chain runs across five repositories, linked by bot version-bump commits:

```
alfresco-community-repo -> alfresco-enterprise-repo -> alfresco-enterprise-share
                        -> acs-packaging -> acs-community-packaging
```

Each repository gates its release jobs on `!(failure() || cancelled())`, so a single flaky test job
stops the whole chain with no notification. Somebody notices hours later and re-runs the failed jobs
by hand, which is exactly what the API can do unattended.

## Shape

A composite action in this repository, plus a small watcher workflow committed to each chain
repository's default branch.

The watcher uses `workflow_run`, which has two properties that carry the design:

- It only registers on, and always executes from, the **default branch**. The `branches:` filter
  applies to the *triggering* run. A watcher on `master` therefore covers `release/23.7` with nothing
  backported to that branch.
- Its filters are evaluated server-side. A run that does not match creates no workflow run at all —
  no entry, no runner, no minutes.

Consumers pin to a commit SHA, per the guidance in [README](README.md).

```yaml
name: Release chain auto-retry

on:
  workflow_run:
    workflows: ["Master/Release branch workflow"]
    types: [completed]
    branches: [master, "release/**"]

permissions:
  actions: write

jobs:
  retry:
    if: contains(fromJSON('["failure","timed_out"]'), github.event.workflow_run.conclusion)
    runs-on: ubuntu-latest
    # Lifted to env because the secrets context cannot be read from a step condition.
    env:
      TEAMS_WEBHOOK: ${{ secrets.TEAMS_WEBHOOK }}
    steps:
      - id: retry
        uses: Alfresco/alfresco-build-tools/.github/actions/release-chain-auto-retry@<sha>

      - name: Report to Teams
        if: steps.retry.outputs.decision == 'escalate' && env.TEAMS_WEBHOOK != ''
        uses: Alfresco/alfresco-build-tools/.github/actions/send-teams-notification@<sha>
        with:
          webhook-url: ${{ secrets.TEAMS_WEBHOOK }}
          title: Release chain stopped in ${{ github.repository }}
          message: ${{ steps.retry.outputs.reason }}
          skip_checkout: "true"

      - name: Fail visibly when no Teams webhook is configured
        if: steps.retry.outputs.decision == 'escalate' && env.TEAMS_WEBHOOK == ''
        env:
          REASON: ${{ steps.retry.outputs.reason }}
        run: |
          echo "::error::$REASON"
          exit 1
```

This file is the same in every chain repository apart from the workflow name it listens for.
Everything else that varies per repository lives in a configuration file instead.

Two checks stay in the workflow rather than moving into the configuration file, because both can be
made before anything is paid for:

- **Branch filtering**, in the `on:` block. `workflow_run` filters are applied server-side, so a run
  on a branch that does not match creates no workflow run at all.
- **The conclusion check**, as a job-level `if:`. A job-level condition is evaluated before a runner
  is allocated, so a successful release run leaves a skipped entry in the Actions tab and costs no
  minutes. Successful runs are the majority, so this is the check that keeps the whole thing cheap.

Anything read from the configuration file necessarily costs a runner, because a file cannot be read
without one.

## Configuration

Each consuming repository owns a `.github/release-auto-retry.yml`:

```yaml
max-attempts: 3        # optional, default: 3 - TOTAL attempts, not retries
non-retryable-jobs:    # required - exact job display names
  - Parse commit metadata
  - Push to Nexus
  - Update alfresco-enterprise-repo
```

**A missing file means disabled.** There is no `enabled` key: the retry is on when the watcher
workflow is present and not disabled, and the configuration file exists. Both are already visible —
the first in the Actions tab, the second in the repository — and a third switch would only give an
incident responder a third place to look.

The action reads the file through
`repos/{owner}/{repo}/contents/.github/release-auto-retry.yml` rather than checking the repository
out — a single call, and it avoids cloning a large repository to read a few lines. Both `yq` and the
GitHub CLI are preinstalled on the standard Ubuntu runners.

Three properties follow from putting the configuration in a file on the default branch:

- It is visible to the people who maintain the repository. `git blame`, pull request review and
  `CODEOWNERS` all apply to it.
- A branch cannot change how its own failures are handled. The watcher runs from the default branch
  and reads the configuration from the default branch, so a pull request has no effect until merged.
- One file covers every branch. `release/23.7` is governed by the copy on `master`, with nothing
  backported.

Both files are added in a single pull request per repository, which is also how the rollout is
staged. Until that pull request lands there is no watcher, so an unconverted repository costs
nothing at all.

### Turning it off

```bash
gh workflow disable "Release chain auto-retry" --repo Alfresco/alfresco-community-repo
```

Immediate, needs no pull request, and the Actions tab then shows the workflow as disabled manually.
A disabled workflow does not fire, so this also costs nothing while it is off.

GitHub disables workflows automatically after 60 days of repository inactivity, but only scheduled
ones. A `workflow_run` watcher in an active repository will not switch itself off.

The trade is that the off state is not recorded in git. If that turns out to matter, an `enabled`
key can be added later without breaking anything, since an absent key would mean enabled.

### Alternatives considered

A repository or organisation variable read in a job-level `if:` would skip before a runner is
allocated, which is marginally cheaper than disabling the workflow and considerably cheaper than
reading a file. It was not used because access to variables is restricted in this organisation, so
a setting that decides whether the release chain repairs itself would be invisible to most of the
people maintaining these repositories.

That trade is worth revisiting if variable visibility changes. The mechanism works; it was rejected
on who can see it, not on how it behaves.

## Decision sequence

The action retries only when every one of these holds:

1. `.github/release-auto-retry.yml` exists on the default branch.
2. **No non-retryable job failed.** Checked against the `non-retryable-jobs` denylist.
3. **The branch has not moved on.** `github.event.workflow_run.head_sha` must still be the tip of
   `head_branch`.
4. `run_attempt` is below `max-attempts`.

Neither the branch nor the run conclusion is checked here. The `on:` block and the job-level `if:`
have already done both, before any runner was allocated. `failure` and `timed_out` are treated
identically — whether a job timed out says nothing about whether it is safe to re-run.

Then: `gh run rerun <id> --failed --repo <owner/repo>`.

Three details that are easy to get wrong:

- `gh run rerun` resolves the repository from the local git remote, and a watcher has no checkout.
  The repository must be passed explicitly.
- `--failed` re-runs failed jobs *inside the existing run*, incrementing `run_attempt`. The retry
  budget therefore needs no stored state, and the completed new attempt fires the next `workflow_run`
  event by itself.
- A re-run replays the **original commit**, not the branch tip. That is what guard 3 exists for: a
  retry that succeeds against a superseded commit would push artifacts and a downstream version bump
  built from stale code, while the newer run releases the current code separately.

### Matching job names

Failed jobs come from
`repos/{owner}/{repo}/actions/runs/{id}/attempts/{n}/jobs`, which returns **display names**, not YAML
keys. Three rules follow from the data in [Collected per-repository values](#collected-per-repository-values):

- **Match exactly, never by substring.** `Parse commit metadata` appears three times in one
  `alfresco-enterprise-repo` run — once flat and twice behind a nested-workflow prefix. A substring
  denylist would block every retry in that repository.
- **Deny the release jobs rather than allowing the test jobs.** Top-level release jobs are flat and
  stable across branches. Test jobs arrive prefixed (`run_ci / `, `alfresco_enterprise_share / `)
  and matrix jobs that never started report their name expression unexpanded, for example
  `run_ci / Repository - MariaDB ${{ matrix.version }} tests`.
- **Treat `skipped` as "did not run".** A gated release job reports `skipped` on a failed attempt,
  not `failure`.

## Action inputs

Behaviour is configured per repository in the file described above. The action itself takes only
what cannot live in a file:

```yaml
      - uses: Alfresco/alfresco-build-tools/.github/actions/release-chain-auto-retry@<sha>
        with:
          config-path: .github/release-auto-retry.yml   # optional, default shown
          github-token: ${{ github.token }}            # optional, default shown
```

It produces `decision` (`retry`, `escalate` or `none`), `reason`, `failed-jobs`, `attempt` and
`max-attempts`.

`max-attempts` in the configuration file counts total attempts including the first, matching
`dependabot-workflow-run-automation`. A value of `3` permits two retries.

### Per-job attempt limits

Not in the first version. The mechanism is understood and the data is available, but the overrides
should be chosen from observed flakiness rather than guessed up front.

`run_attempt` belongs to the run, not to a job, so there is no per-job counter in the event payload.
One can be derived by walking `attempts/1..n/jobs` and counting failures per display name — at most
two extra API calls at the default budget.

Because the run's conclusion depends on every job, retrying a subset cannot turn the run green. A
per-job limit can therefore only decide whether to retry at all. The useful reading is: retry while
every failed job is within its own budget, and stop as soon as one has exhausted it. That lets a
known-flaky job have more chances while a normally-reliable job failing twice stops the loop early
instead of spending another two hours of runner time.

## Escalation

Two outcomes escalate, and only these two:

1. The retry budget is spent and the run is still failing.
2. A non-retryable job failed, so no retry was attempted at all.

A successful retry is silent. Reporting success-after-retry is useful for spotting flaky jobs but is
out of scope here — it is tracked separately on ACS-13044.

The action does not send the notification itself. It reports `decision: escalate` and a `reason`, and
the watcher passes those to [send-teams-notification](README.md#send-teams-notification) in a
following step.

That split is deliberate. A composite action calling another action from the same repository is not a
pattern used anywhere else here, and relative references inside a composite action resolve against the
consuming repository rather than this one. Keeping the call in the watcher uses
`send-teams-notification` exactly as it is already used elsewhere, and leaves the decision logic as a
shell script that can be tested without a network.

Opening a GitHub issue was considered and dropped — it would need a process change across several
teams.

No chain repository has a Teams webhook secret today. Until one exists the watcher reports an
escalation by failing with the reason in the log, so the rollout does not have to wait for it. Retries
are unaffected either way, because the reporting steps only run on the escalate path.

Teams needs only a webhook secret, so no GitHub App token is required anywhere.

## Collected per-repository values

The values each repository needs: the workflow name for its watcher's `on:` block, and the job list
for its `.github/release-auto-retry.yml`. Collected 2026-10-19 from the most recent completed `push`
run on `master` in each repository.

| Repository | Workflow file | `name:` |
|---|---|---|
| alfresco-community-repo | `master_release.yml` | Master/Release branch workflow |
| alfresco-enterprise-repo | `master_release.yml` | Master/Release branch workflow |
| alfresco-enterprise-share | `release.yml` | release |
| acs-packaging | `master_release.yml` | Master/Release branch workflow |
| acs-community-packaging | `ci.yml` | ACS Community Packaging CI |

Non-retryable job display names, for `non-retryable-jobs`:

| Repository | Jobs |
|---|---|
| alfresco-community-repo | `Parse commit metadata`, `Push to Nexus`, `Update alfresco-enterprise-repo` |
| alfresco-enterprise-repo | `Parse commit metadata`, `Push to Nexus`, `Update alfresco-enterprise-share`, `Update acs-packaging` |
| alfresco-enterprise-share | `Parse commit metadata`, `release`, `update_downstream`, `mirroring` |
| acs-packaging | `Parse commit metadata`, `Update latest and Single Pipeline <acs>-<build> images`, `Release and Copy to S3 Staging Bucket`, `Update acs-community-packaging (after release)` |
| acs-community-packaging | `Update latest Docker images`, `Release and Copy to S3 Staging Bucket` |

`alfresco-enterprise-share` declares no `name:` on its top-level jobs, so the display names are the
YAML keys. Its list is not interchangeable with the others.

On `release/23.7`, `alfresco-community-repo` has no `Parse commit metadata` job but the remaining
names are identical to `master`. A denylist entry that matches nothing is harmless, so one list per
repository covers every branch.

## Evidence

Behaviour below was confirmed on a scratch repository on 2026-10-19 rather than assumed.

| Question | Result |
|---|---|
| Does a watcher on the default branch fire for a run on another branch? | Yes |
| Does an explicit `permissions: actions: write` survive a read-only repository default? | Yes |
| Can `GITHUB_TOKEN` re-run failed jobs? | Yes |
| Does a `GITHUB_TOKEN`-initiated re-run fire a fresh `workflow_run` event? | Yes |
| Does the attempt budget stop the loop? | Yes — attempts 1, 2, 3, then escalation |

That fourth row is why this is a composite action using `GITHUB_TOKEN` rather than a reusable
workflow using a GitHub App token. The retry loop sustains itself without an App token. Escalation
targets outside Actions may still need separate credentials.

Latency between a failed attempt completing and the retry starting was roughly 20 seconds, against
release builds that run between one and two hours.

## Known limitations

- **Guard 3 is a check, not a lock.** A commit can land between reading the branch tip and calling
  `gh run rerun`; GitHub offers no atomic compare-and-rerun. The window is a few seconds. This is the
  same limitation the `git-branch-drift` check added to `maven-release-slim` in
  [PR 1522](https://github.com/Alfresco/alfresco-build-tools/pull/1522) describes for itself.
- **Guard 3 will rarely fire in production.** The watcher starts within roughly 20 seconds of a run
  failing, so the branch has to move inside that window. At the observed rate of about two runs a day
  per repository that is close to never, which means its behaviour has to be established by tests
  rather than by use.
- **Retrying extends a run's lifetime**, which makes overlap with a following run more likely. None
  of the release workflows declare a `concurrency` group today. Adding one belongs to ACS-13044, not
  here.
- **A `git-branch-drift` abort is a benign failure that still escalates.** It is not retryable and
  will page somebody.
- On private repositories each *executing* watcher job is billed at the one-minute minimum, and a
  watcher executes on every failed release run whether or not it ends up retrying. Successful runs
  skip before a runner is allocated and cost nothing. At the observed rate of roughly one
  retry-eligible failure every two days per repository this is negligible.
