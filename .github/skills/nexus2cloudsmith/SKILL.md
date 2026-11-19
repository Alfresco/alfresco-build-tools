---
name: nexus2cloudsmith
description: "Migrate a Maven repository's CI from the Alfresco Nexus (artifacts.alfresco.com) to Cloudsmith (artifacts.hyland.dev), for pulling dependencies (Phase 1) and deploying releases (Phase 2). Use when: replacing artifacts.alfresco.com URLs in pom.xml or settings.xml; swapping NEXUS_USERNAME/NEXUS_PASSWORD secrets for the cloudsmith-auth OIDC action; moving distributionManagement to Cloudsmith; working on a 'Cloudsmith Migration - Phase 1 (Pull)' or 'Phase 2 (Push)' ticket."
---

# Migrate Maven CI from Nexus to Cloudsmith

Nexus becomes a frozen archive: versions published before the cutover stay
there, but new releases (Alfresco 26.3.0 onwards and the components released
with it) go only to Cloudsmith. A repo needs Phase 1 as soon as it depends on
any of them.

The migration has two phases, usually one PR each:

1. **Pull**: resolve dependencies and plugins from Cloudsmith.
2. **Push**: deploy release artifacts to Cloudsmith.

Do only the phase the user asked for. If they didn't say, do the next one
according to the Step 0 survey.

## Step 0: Survey the repo

```bash
git grep -n -i -E "artifacts\.alfresco\.com|nexus|cloudsmith|snapshot|MAVEN_USERNAME|MAVEN_PASSWORD" \
  -- '*pom.xml' '*settings*.xml' '*.yml' '*.yaml' '*.md' '*Dockerfile*' '*.sh'
gh repo view --json visibility --jq .visibility
```

Keep the grep output: later steps check it instead of searching again. If
`<repository>` or mirror URLs still point at Nexus, or no job has a
`cloudsmith-auth` step, Phase 1 is next. If only the `distributionManagement`
URLs and the `NEXUS_*` secrets of the release job remain, Phase 2 is next.

Phase 1 follows who can build the source, so it depends on the repo's
visibility: `PUBLIC` follows "Public repo", `PRIVATE` / `INTERNAL` follows
"Private repo".

Phase 2 follows who consumes each module's artifacts, so it depends on the
module's class. From the grep, note each module's Nexus
`distributionManagement` URL:

- `nexus/content/repositories/releases`: **community** module, even in a
  private repo. Its artifacts ship in the community distribution.
- `nexus/content/repositories/enterprise-releases`: **enterprise** module.
- No Nexus deploy URL: community in a public repo, enterprise in a private or
  internal one.

Confirm a community module of a private repo with its latest release, which
returns 200 from `alfresco-public` without credentials. One module per
distinct deploy URL is enough:

```bash
curl -sI -o /dev/null -w '%{http_code}\n' \
  https://artifacts.hyland.dev/public/alfresco-public/maven/<group/path>/<artifactId>/<version>/<artifactId>-<version>.pom
```

Ask the user when the signals conflict: an `enterprise-releases` module in a
public repo, or a `releases` module whose release doesn't return 200.

### Check the Cloudsmith workspace

If the `cloudsmith` CLI is installed and logged in, confirm each repository
the chosen path needs exists:

```bash
cloudsmith list repos hyland/<repository>
```

If one is missing, stop and tell the user instead of pointing a pom at it.
Without the CLI, trust the table below.

## URL mapping

The repository roles and URLs come from the Confluence pages listed under
[Sources](#sources). If you can read them, check them for changes first.

| Nexus | Cloudsmith | Auth |
| --- | --- | --- |
| `nexus/content/groups/public` | `https://artifacts.hyland.dev/public/alfresco-public/maven/` | anonymous |
| Maven Central, public repos | `https://artifacts.hyland.dev/basic/cic-ext-pull-through/maven/` | cloudsmith-auth |
| `nexus/content/groups/internal` | `https://artifacts.hyland.dev/basic/alfresco-internal/maven/` | cloudsmith-auth |
| `nexus/content/repositories/releases` | `https://artifacts.hyland.dev/basic/alfresco-community-releases/maven/` | cloudsmith-auth |
| `nexus/content/repositories/enterprise-releases` | `https://artifacts.hyland.dev/basic/alfresco-enterprise-releases/maven/` | cloudsmith-auth |
| none: `-A.x` releases of enterprise modules, internal tools, unreleased products | `https://artifacts.hyland.dev/basic/alfresco-internal-releases/maven/` | cloudsmith-auth |
| `nexus/content/repositories/activiti-releases` | `https://artifacts.hyland.dev/public/activiti-releases/maven/` | anonymous |
| `nexus/content/repositories/activiti-enterprise-releases` | `https://artifacts.hyland.dev/basic/activiti-enterprise-releases/maven/` | cloudsmith-auth |
| any `*-snapshots` repository | drop it | n/a |

`alfresco-public`, `alfresco-internal` and `cic-ext-pull-through` are pull
only; deploys use a different host (see Phase 2). `alfresco-private` serves
customers and partners: never use it in CI. For a Nexus repository not in
this table (thirdparty, for example), stop and ask the user for the target.

The Alfresco repositories have no snapshots, by design: mutable artifacts make
builds non-deterministic. Projects release `-A.x` versions instead, on demand
or at most weekly on a schedule, never on every push to master. Remove jobs
that deploy `-SNAPSHOT` versions (for example `publish_snapshot_artifacts`
and its entries in other jobs' `needs:`), and switch a phase that becomes
`deploy` on pushes to master back to `verify`.

Before removing a snapshot job, read the scripts and Maven profiles it runs.
If they also publish something else, such as a `-Pinternal` profile pushing a
`:latest` Docker image, tell the user what stops being published instead of
dropping it silently.

Binary downloads from `nexus.alfresco.com/nexus/service/local/...` (in
Dockerfiles or CI scripts) are not Maven resolution and are out of scope.
Leave them and mention them to the user.

## Phase 1: Pull

### Public repo

A public repo pulls only from `alfresco-public` and Maven Central, never from
`alfresco-internal` or `alfresco-internal-releases`: community users can't
read them.

In `pom.xml`, change the `alfresco-public` `<repository>` and
`<pluginRepository>` URLs (add them if the repo relied on a settings-file
profile or mirror instead), and drop the snapshot repositories:

```xml
<repository>
    <id>alfresco-public</id>
    <name>Alfresco Public Repository</name>
    <url>https://artifacts.hyland.dev/public/alfresco-public/maven/</url>
    <releases>
        <enabled>true</enabled>
    </releases>
    <snapshots>
        <enabled>false</enabled>
    </snapshots>
</repository>
```

`alfresco-public` doesn't proxy Central, so declare `central` first in both
`<repositories>` and `<pluginRepositories>`. Otherwise every Central artifact
costs a 404 from `alfresco-public` first:

```xml
<pluginRepositories>
    <pluginRepository>
        <id>central</id>
        <name>Central Repository</name>
        <url>https://repo.maven.apache.org/maven2</url>
        <layout>default</layout>
        <snapshots>
            <enabled>false</enabled>
        </snapshots>
    </pluginRepository>
    <pluginRepository>
        <id>alfresco-public</id>
        <name>Alfresco Public Repository</name>
        <url>https://artifacts.hyland.dev/public/alfresco-public/maven/</url>
        <snapshots>
            <enabled>false</enabled>
        </snapshots>
    </pluginRepository>
</pluginRepositories>
```

Remove any `alfresco-internal` profile, mirror or server from the settings
files, and drop the `NEXUS_*` env from build jobs. In `.ci.settings.xml`,
mirror only `central` to `cic-ext-pull-through`. Every CI job that runs Maven,
the release included, must resolve Central through it: supply-chain policy
requires it. It serves only Central, so enterprise artifacts can't leak into a
community build, and `alfresco-public` stays anonymous:

```xml
<settings>
    <mirrors>
        <mirror>
            <id>cic-ext-pull-through</id>
            <name>Maven Central</name>
            <url>https://artifacts.hyland.dev/basic/cic-ext-pull-through/maven/</url>
            <mirrorOf>central</mirrorOf>
        </mirror>
    </mirrors>

    <servers>
        <!-- Exported by the cloudsmith-auth action -->
        <server>
            <id>cic-ext-pull-through</id>
            <username>${env.CLOUDSMITH_USERNAME}</username>
            <password>${env.CLOUDSMITH_API_KEY}</password>
        </server>
    </servers>
</settings>
```

Prove that `alfresco-public` and Maven Central are enough by resolving locally
with an empty settings file (see Verify). That is a local check only: don't
run CI jobs with empty settings, as that skips `cic-ext-pull-through`. If
something only resolves from an authenticated repository, stop and tell the
user which artifacts: they have to be published to a repository
`alfresco-public` serves, or dropped.

Known limitation: GitHub gives no OIDC token to PRs from forks, so their builds
fail at `cloudsmith-auth`. PRs from forks aren't supported for now. Mention it
to the user, but don't work around it by skipping `cloudsmith-auth` or
`cic-ext-pull-through`.

### Private repo

In `.ci.settings.xml`, replace the `alfresco-internal` profile and its
repositories with a single mirror. `mirrorOf *` is fine because
`alfresco-internal` proxies Maven Central:

```xml
<settings>
    <mirrors>
        <mirror>
            <id>alfresco-internal</id>
            <name>Alfresco Internal</name>
            <url>https://artifacts.hyland.dev/basic/alfresco-internal/maven/</url>
            <mirrorOf>*</mirrorOf>
        </mirror>
    </mirrors>

    <servers>
        <!-- Exported by the cloudsmith-auth action -->
        <server>
            <id>alfresco-internal</id>
            <username>${env.CLOUDSMITH_USERNAME}</username>
            <password>${env.CLOUDSMITH_API_KEY}</password>
        </server>
        <!-- keep the existing deploy servers until Phase 2 -->
    </servers>
</settings>
```

If the build also pulls from a repository that Cloudsmith doesn't proxy (GitHub
Packages, for example), exclude its id: `<mirrorOf>*,!github</mirrorOf>`.

Remove `<server>` entries whose repository no longer exists (the other
internal, public and thirdparty ids). Keep the deploy servers that still use
`MAVEN_USERNAME` / `MAVEN_PASSWORD`, because Phase 2 replaces those.

The mirror overrides the pom's repositories in CI, but local builds still use
them. Apply the URL mapping table to every `<repository>` and
`<pluginRepository>` in the poms that still points at `artifacts.alfresco.com`.

### All repos

Grant `id-token: write` and add [`cloudsmith-auth`][cloudsmith-auth] before
the first step that runs Maven in **every** job that runs it, including the
release job and `dependency-graph.yml`. Put it after `setup-java-build` where
the job has one; `maven-dependency-scan` sets up Java itself. Add
`id-token: write` to the job's existing `permissions:` and keep the scopes
already there: any scope a `permissions:` block leaves out becomes `none`, so
a release job would lose `contents: write`.

Pin `cloudsmith-auth` to the same ref as the repo's other build-tools actions
if that ref already has it. Otherwise use the latest release
(`gh api repos/Alfresco/alfresco-build-tools/releases/latest --jq .tag_name`).
A tag is fine, see
[pimp-my-repo](https://github.com/Alfresco/alfresco-build-tools/blob/master/.github/skills/pimp-my-repo/SKILL.md#wire-into-ci).

[cloudsmith-auth]: https://github.com/Alfresco/alfresco-build-tools/blob/master/docs/README.md#cloudsmith-auth

```yaml
permissions:
  id-token: write
  contents: read  # keep whatever the job already had

steps:
  - uses: Alfresco/alfresco-build-tools/.github/actions/setup-java-build@vX.Y.Z
  - uses: Alfresco/alfresco-build-tools/.github/actions/cloudsmith-auth@vX.Y.Z
    with:
      oidc-namespace: ${{ vars.CLOUDSMITH_NAMESPACE }}
```

In `dependency-graph.yml`, drop the `maven-username` / `maven-password` inputs
fed from `NEXUS_*` secrets on `maven-dependency-scan`. They only set
`MAVEN_USERNAME` / `MAVEN_PASSWORD`, which the settings no longer read.

If `.github/dependabot.yml` declares a Nexus `maven-repository` registry,
delete it, together with its name in the `registries:` list of each update
(drop the list if it becomes empty). Private and internal repos get
`alfresco-internal` from an org-level registry that authenticates with OIDC.
Public repos resolve from the `alfresco-public` repository in their pom.

## Phase 2: Push

Each module deploys according to its class from Step 0:

| Module class | GA and M versions | `-A.x` versions | `alfresco_publish_targets` |
| --- | --- | --- | --- |
| community | `alfresco-community-releases` | `alfresco-community-releases` | `community_releases` |
| enterprise | `alfresco-enterprise-releases` | `alfresco-internal-releases`, through the `prerelease` profile | `enterprise_releases`, `internal_releases` |

Community `-A.x` releases stay with the GA ones because community users can't
read `alfresco-internal-releases`.

### `pom.xml`

Keep one `<repository>` in `distributionManagement`, pointing at the GA
repository, and drop `<snapshotRepository>`. Deploy through
`maven.cloudsmith.io`, Cloudsmith's Maven upload endpoint:
`artifacts.hyland.dev` serves downloads only and refuses uploads with a 403.

```xml
<distributionManagement>
    <repository>
        <id>alfresco-releases</id>
        <name>Alfresco Community Releases</name>
        <!-- TODO: switch to maven.artifacts.hyland.dev once its DNS record exists -->
        <url>https://maven.cloudsmith.io/hyland/alfresco-community-releases/</url>
    </repository>
</distributionManagement>
```

For enterprise modules, use `Alfresco Enterprise Releases` and the
`alfresco-enterprise-releases` URL, and add a `prerelease` profile that sends
`-A.x` releases to `alfresco-internal-releases`. It reuses the
`alfresco-releases` server, so no new credentials are needed:

```xml
<profiles>
    <profile>
        <id>prerelease</id>
        <distributionManagement>
            <repository>
                <id>alfresco-releases</id>
                <name>Alfresco Internal Releases</name>
                <!-- TODO: switch to maven.artifacts.hyland.dev once its DNS record exists -->
                <url>https://maven.cloudsmith.io/hyland/alfresco-internal-releases/</url>
            </repository>
        </distributionManagement>
    </profile>
</profiles>
```

Put `distributionManagement`, and the `prerelease` profile for enterprise
modules, in the highest pom whose inheriting modules all share one class, and
drop module blocks that only repeat it. A module whose class differs from its
parent's, or that has to keep its own `distributionManagement`, declares its
own block and, if enterprise, its own `prerelease` profile: its block wins
over an inherited profile, so its `-A.x` releases would otherwise land in the
GA repository.

### `.ci.settings.xml`

Replace the Nexus deploy servers (`alfresco-public-releases`,
`alfresco-public-snapshots`, `alfresco-enterprise-releases`,
`alfresco-enterprise-snapshots`, ...) with one server, next to the Phase 1
mirror server:

```xml
<server>
    <id>alfresco-releases</id>
    <username>${env.CLOUDSMITH_USERNAME}</username>
    <password>${env.CLOUDSMITH_API_KEY}</password>
</server>
```

### Release workflow

- Check that the release job has the Phase 1 `cloudsmith-auth` step and
  `id-token: write`.
- Remove `MAVEN_USERNAME: ${{ secrets.NEXUS_USERNAME }}` and
  `MAVEN_PASSWORD: ${{ secrets.NEXUS_PASSWORD }}`, whether they sit at job or
  workflow level, once the Step 0 grep shows nothing else reads them.
- Repos with enterprise modules: turn on the `prerelease` profile for `-A.x`
  versions. [`maven-release-slim`][maven-release-slim] does it when
  `prerelease-profile` is set. The input needs v19.8.0 or later, so bump the
  action if the repo pins an older one:

  ```yaml
  - uses: Alfresco/alfresco-build-tools/.github/actions/maven-release-slim@v19.16.0
    with:
      token: ${{ steps.app-token.outputs.token }}
      release-version: ${{ env.RELEASE_VERSION }}
      development-version: ${{ env.DEVELOPMENT_VERSION }}
      prerelease-profile: prerelease
  ```

  If the job runs `mvn deploy` directly, add `-Pprerelease` to that command
  when the version contains `-A.`.

[maven-release-slim]: https://github.com/Alfresco/alfresco-build-tools/blob/master/docs/README.md#maven-release-slim

### Testing the deploy before merge

PR CI skips the release job, so the deploy path only runs on a real release.
If the user wants to try it from the PR branch:

- Release an `-A.x` version, so an enterprise module lands in
  `alfresco-internal-releases` and not in a GA repository. A community
  module's `-A.x` lands in `alfresco-community-releases`, so ask the user
  first.
- Before merge, revert the test `RELEASE_VERSION` and the branch added to the
  release job's `if:`.
- Squash-merge, so the release plugin's `[skip ci]` commits don't reach the
  default branch.
- Ask the user to delete the test tag and the test package in Cloudsmith.

### If auth or deploy is denied

Access is granted in `HylandPlatformConfiguration/tf-config-cloudsmith`, in
`locals-alfresco.tf`, not in the repo being migrated. Don't work around it in
the workflow: raise a PR there, with the Jira key in the branch name.

That repo is DevOps-only. If you can't open it (no local clone, `gh` returns
404), the user lacks access: tell them to ask the DevOps team for the change,
giving the repo name and the exact edit below. Don't try to reach it another
way.

- `cloudsmith-auth` fails (and the repo is not a fork): add the repo name, spelled
  as GitHub spells it, to the read list (`alfresco_read_repositories`).
- Deploy fails with 403: add the repo to `alfresco_publish_targets` with the
  targets of its module classes, from the Phase 2 table.
- Keep both lists sorted. Each target is a deliberate, reviewable grant: don't
  add a broader write group to make the change smaller.

### Docs

Update the README and any docs that mention Nexus, following the naming rule
in Rules. Browse links for the public repository go to
`https://artifacts.hyland.dev/public/alfresco-public/maven/`.

## Rules

- Use no `cloudsmith.io` URL other than the `maven.cloudsmith.io` deploy URLs
  of Phase 2, and keep the TODO comment above each of them.
- Don't name Cloudsmith in ids, names, job names, comments or docs, so the next
  registry move doesn't mean renaming them. Use neutral ids
  (`alfresco-public`, `alfresco-internal`, `alfresco-releases`) or the
  Cloudsmith repository name (`cic-ext-pull-through`). Where "Nexus" appears,
  reword without naming a registry ("deploy to the Maven repository") rather
  than replacing it with "Cloudsmith". Use "Cloudsmith" only where it can't be
  avoided: URLs, the `cloudsmith-auth` step and the `CLOUDSMITH_*` variables
  it exports. Exception: projects generated with the In-Process Alfresco SDK,
  and the SDK itself, keep the archetype's ids (`alfresco-plugin-public`,
  `alfresco-private-repository`).
- Only name ids in comments that exist in the file.

## Verify

```bash
# No Nexus left
git grep -n -E "artifacts\.alfresco\.com|NEXUS_(USERNAME|PASSWORD)"

# Public repos: resolves with no credentials and an empty local repository
scratch="${TMPDIR:-/tmp}/nexus2cloudsmith"
mkdir -p "$scratch/m2"
echo '<settings/>' >| "$scratch/settings.xml"
mvn -B -ntp -s "$scratch/settings.xml" -Dmaven.repo.local="$scratch/m2" \
  dependency:go-offline && rm -rf "$scratch"
```

The empty local repository matters: a warm `~/.m2` hides artifacts that only
came from an authenticated repository. Run it once all pom edits are done. On
a failure, keep `$scratch/m2` for the retry: it only holds what the anonymous
settings could resolve.

When an artifact fails to resolve, check whether a repository has it.
`display_source: upstream` means Cloudsmith proxied it, for example from
Maven Central:

```bash
cloudsmith list pkgs hyland/alfresco-internal -q "name:<artifactId> version:<version>" -F json
```

For private repos, the build can only be checked in CI because it needs the
OIDC token. Run pre-commit (and `actionlint` if the repo uses it) before
pushing.

## PR

Open one PR per phase, titled like the existing ones:
`[<JIRA-ID>] Cloudsmith Migration - Phase 1 (Pull) - <repo>` or
`... Phase 2 (Push) - <repo>`, with no colon after the bracket. If one PR
covers both, say `Phase 1 (Pull) and Phase 2 (Push)`. Ask the user for the
Jira ID if you don't have it.

Open the description with the phase too. A Pull PR leaves the deploy side on
Nexus on purpose, so list what stays there until the other phase (the
`distributionManagement` URLs, the `NEXUS_*` secrets on the release job), or
reviewers flag it as a mistake.

When reviewing a migration PR, check its phase first and judge it against
that phase only. If the title doesn't name a phase, ask for it.

## Sources

- [Maven Repositories](https://hyland.atlassian.net/wiki/spaces/TECH/pages/4303717170/Maven+Repositories):
  what each Cloudsmith repository is for, and which ones pull or push.
- [Cloudsmith Alfresco Consumption](https://hyland.atlassian.net/wiki/spaces/cix/pages/4313722570/Cloudsmith+Alfresco+Consumption):
  OIDC authentication, the Dependabot account and the `maven.cloudsmith.io`
  upload endpoint. It is still a draft.
- [Migrating your CI to the Hyland artifact repository for Alfresco](https://community.hyland.com/discussion/501538/migrating-your-ci-to-the-hyland-artifact-repository-for-alfresco):
  the public guide for customers and community users, with the Activiti
  repositories and the Nexus archive cutover.
