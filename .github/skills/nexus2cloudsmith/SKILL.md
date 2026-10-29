---
name: nexus2cloudsmith
description: "Migrate a Maven repository's CI from the Alfresco Nexus (artifacts.alfresco.com) to Cloudsmith (artifacts.hyland.dev), for pulling dependencies (Phase 1) and deploying releases (Phase 2). Use when: replacing artifacts.alfresco.com URLs in pom.xml or settings.xml; swapping NEXUS_USERNAME/NEXUS_PASSWORD secrets for the cloudsmith-auth OIDC action; moving distributionManagement to Cloudsmith; working on a 'Cloudsmith Migration - Phase 1 (Pull)' or 'Phase 2 (Push)' ticket."
---

# Migrate Maven CI from Nexus to Cloudsmith

## When to Use

- `pom.xml`, `.ci.settings.xml` or a workflow still points at `artifacts.alfresco.com/nexus`
- Workflows pass `secrets.NEXUS_USERNAME` / `secrets.NEXUS_PASSWORD` to Maven
- A Jira ticket asks for "Cloudsmith Migration - Phase 1 (Pull)" or "Phase 2 (Push)"

Nexus becomes a frozen archive: versions published before the cutover stay
there, but new releases (Alfresco 26.3.0 onwards and the components released
with it) go only to Cloudsmith. A repo needs Phase 1 as soon as it depends on
any of them.

The migration has two phases, usually one PR each:

1. **Pull**: resolve dependencies and plugins from Cloudsmith.
2. **Push**: deploy release artifacts to Cloudsmith.

Do only the phase the user asked for. If they didn't say, check which one is
already done and do the next one.

## Step 0: Survey the repo

```bash
git grep -n -i -E "artifacts\.alfresco\.com|nexus|MAVEN_USERNAME|MAVEN_PASSWORD" \
  -- '*pom.xml' '*settings*.xml' '*.yml' '*.yaml' '*.md'
gh repo view --json visibility --jq .visibility
```

Keep the grep output: later steps check it instead of searching again. The
visibility picks the Phase 1 path: `PUBLIC` follows "Public repo",
`PRIVATE` / `INTERNAL` follows "Private repo".

### Check the Cloudsmith workspace

If the `cloudsmith` CLI is installed and logged in (`cloudsmith whoami`),
confirm the repositories the chosen path needs exist:

```bash
cloudsmith list repos hyland --page-size 500
```

If one is missing, stop and tell the user instead of pointing a pom at it.
Without the CLI, trust the table below.

When an artifact fails to resolve, check whether a repository has it.
`display_source: upstream` means Cloudsmith proxied it, for example from
Maven Central:

```bash
cloudsmith list pkgs hyland/alfresco-internal -q "name:<artifactId>" -F json
```

## URL mapping

The repository roles and URLs come from the Confluence pages listed under
[Sources](#sources). If you can read them, check them for changes first.

| Nexus | Cloudsmith | Auth |
| --- | --- | --- |
| `nexus/content/groups/public` | `https://artifacts.hyland.dev/public/alfresco-public/maven/` | anonymous |
| Maven Central, public repos | `https://artifacts.hyland.dev/basic/cic-ext-pull-through/maven/` | cloudsmith-auth |
| `nexus/content/groups/internal` | `https://artifacts.hyland.dev/basic/alfresco-internal/maven/` | cloudsmith-auth |
| `nexus/content/repositories/releases`, GA and M versions | `https://artifacts.hyland.dev/basic/alfresco-community-releases/maven/` | cloudsmith-auth |
| `nexus/content/repositories/enterprise-releases`, GA and M versions | `https://artifacts.hyland.dev/basic/alfresco-enterprise-releases/maven/` | cloudsmith-auth |
| any release repository, `-A.x` versions (also internal tools, unreleased products) | `https://artifacts.hyland.dev/basic/alfresco-internal-releases/maven/` | cloudsmith-auth |
| `nexus/content/repositories/activiti-releases` | `https://artifacts.hyland.dev/public/activiti-releases/maven/` | anonymous |
| `nexus/content/repositories/activiti-enterprise-releases` | `https://artifacts.hyland.dev/basic/activiti-enterprise-releases/maven/` | cloudsmith-auth |
| any `*-snapshots` repository | drop it | n/a |

`alfresco-public`, `alfresco-internal` and `cic-ext-pull-through` are pull
only. `artifacts.hyland.dev` is a download-only domain, so deploys to the
release repositories go to `https://maven.cloudsmith.io/hyland/<repository>/`
instead (see Phase 2).
`alfresco-private` serves customers and partners: never use it in CI. For a
Nexus repository not in this table (thirdparty, for example), stop and ask
the user for the target.

The Alfresco repositories have no snapshots, by design: mutable artifacts make
builds non-deterministic. Projects release `-A.x` versions instead, on demand
or at most weekly on a schedule, never on every push to master. Remove jobs
that deploy `-SNAPSHOT` versions (for example `publish_snapshot_artifacts`
and its entries in other jobs' `needs:`), and switch a phase that becomes
`deploy` on pushes to master back to `verify`. The `activiti-*-snapshots`
repositories serve another purpose: don't use them.

Before removing a snapshot job, read the scripts and Maven profiles it runs.
If they also publish something else, such as a `-Pinternal` profile pushing a
`:latest` Docker image, tell the user what stops being published instead of
dropping it silently.

Binary downloads from `nexus.alfresco.com/nexus/service/local/...` (in
Dockerfiles or CI scripts) are not Maven resolution and are out of scope.
Leave them and mention them to the user.

## Phase 1: Pull

### Public repo

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
the release included, must resolve Central through it rather than from Maven
Central directly: supply-chain policy requires all Central downloads to pass
through Cloudsmith. It serves only Central, so enterprise artifacts can't leak
into a community build, and `alfresco-public` stays anonymous:

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
something only resolves from
`internal`, stop and tell the user which artifacts. Don't switch to
`alfresco-internal`: the dependency has to be published publicly or dropped.

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

Grant `id-token: write` and add
[`cloudsmith-auth`](https://github.com/Alfresco/alfresco-build-tools/blob/master/docs/README.md#cloudsmith-auth) before the
first step that runs Maven in **every** job that runs it, including
`dependency-graph.yml`. Put it after `setup-java-build` where the job has
one; `maven-dependency-scan` sets up Java itself. Add `id-token: write` to the job's existing
`permissions:` and keep the scopes already there: any scope a `permissions:`
block leaves out becomes `none`, so a release job would lose `contents: write`.

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

### `pom.xml`

Keep one `<repository>` in `distributionManagement`, pointing at the GA
repository from the mapping table, and drop `<snapshotRepository>`. Deploy
through `maven.cloudsmith.io`, Cloudsmith's Maven upload endpoint:
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

For an enterprise repo, use `Alfresco Enterprise Releases` and the
`alfresco-enterprise-releases` URL.

Add a `prerelease` profile that sends `-A.x` releases to
`alfresco-internal-releases`. It reuses the `alfresco-releases` server, so no
new credentials are needed:

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

A module whose own `distributionManagement` matches the root's should drop
it and inherit. If a module has to keep its own block, give it its own
`prerelease` profile too: the module's block wins over the profile it
inherits, so its `-A.x` releases would otherwise land in the GA repository.

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

- Give the release job `id-token: write` and the `cloudsmith-auth` step (see
  "All repos" in Phase 1) if it doesn't have them yet.
- Remove `MAVEN_USERNAME: ${{ secrets.NEXUS_USERNAME }}` and
  `MAVEN_PASSWORD: ${{ secrets.NEXUS_PASSWORD }}`, whether they sit at job or
  workflow level, once the Step 0 grep shows nothing else reads them.
- Drop "Nexus" from job names and comments rather than renaming it to
  "Cloudsmith".
- Turn on the `prerelease` profile for `-A.x` versions. `maven-release-slim`
  does it when `prerelease-profile` is set (its `prerelease-version-marker`
  defaults to `-A.`). The input needs v19.8.0 or later, so bump the action if
  the repo pins an older one:

  ```yaml
  - uses: Alfresco/alfresco-build-tools/.github/actions/maven-release-slim@v19.8.0
    with:
      token: ${{ steps.app-token.outputs.token }}
      release-version: ${{ env.RELEASE_VERSION }}
      development-version: ${{ env.DEVELOPMENT_VERSION }}
      prerelease-profile: prerelease
  ```

  If the job runs `mvn deploy` directly, add `-Pprerelease` to that command
  when the version contains `-A.`.

### Testing the deploy before merge

PR CI skips the release job, so the deploy path only runs on a real release.
If the user wants to try it from the PR branch:

- Release an `-A.x` version, so the package lands in
  `alfresco-internal-releases` and not in a GA repository.
- Before merge, revert the test `RELEASE_VERSION` and the branch added to the
  release job's `if:`.
- Squash-merge, so the release plugin's `[skip ci]` commits don't reach the
  default branch.
- Ask the user to delete the test tag and the test package in Cloudsmith.

### Docs

Update the README and any docs that mention Nexus. Reword them without naming
a registry ("deploy to the Maven repository") rather than replacing "Nexus"
with "Cloudsmith". Browse links for the public repository go to
`https://artifacts.hyland.dev/public/alfresco-public/maven/`.

## Rules

- Pull from the `artifacts.hyland.dev` URLs and deploy to
  `https://maven.cloudsmith.io/hyland/<repository>/`. Use no other
  `cloudsmith.io` URL. `maven.artifacts.hyland.dev` will replace the deploy
  URL once its DNS record exists, so keep the TODO comment above each deploy
  URL, as in the Phase 2 examples.
- Keep repository and server ids neutral: `alfresco-public`,
  `alfresco-internal`, `alfresco-releases`, or the Cloudsmith repository name
  (`cic-ext-pull-through`). Only name ids in comments that exist in the
  file. Exception: projects generated with the In-Process Alfresco SDK, and
  the SDK itself, keep the archetype's ids (`alfresco-plugin-public`,
  `alfresco-private-repository`).
- Don't name Cloudsmith in ids, names, job names, comments or docs, so the next
  registry move doesn't mean renaming them. Use it only where it can't be
  avoided: URLs, the `cloudsmith-auth` step and the `CLOUDSMITH_*`
  variables it exports.
- Pin `cloudsmith-auth` to the same ref as the repo's other build-tools
  actions if that ref already has it. Otherwise use the latest release
  (`gh api repos/Alfresco/alfresco-build-tools/releases/latest --jq .tag_name`).
  A tag is fine, see
  [pimp-my-repo](https://github.com/Alfresco/alfresco-build-tools/blob/master/.github/skills/pimp-my-repo/SKILL.md#wire-into-ci).
- Use `CLOUDSMITH_USERNAME` / `CLOUDSMITH_API_KEY` only as `${env.…}` in
  settings files, as [`cloudsmith-auth`](https://github.com/Alfresco/alfresco-build-tools/blob/master/docs/README.md#cloudsmith-auth)
  describes.

## Verify

```bash
# No Nexus left
git grep -n -E "artifacts\.alfresco\.com|NEXUS_(USERNAME|PASSWORD)"

# Public repos: resolves with no credentials and an empty local repository
scratch="${TMPDIR:-/tmp}/nexus2cloudsmith"
mkdir -p "$scratch/m2"
echo '<settings/>' >| "$scratch/settings.xml"
mvn -B -s "$scratch/settings.xml" -Dmaven.repo.local="$scratch/m2" dependency:go-offline
rm -rf "$scratch"
```

The empty local repository matters: a warm `~/.m2` hides artifacts that only
came from an authenticated repository.

For private repos, the build can only be checked in CI because it needs the
OIDC token. Run pre-commit (and `actionlint` if the repo uses it) before
pushing.

## PR

Open one PR per phase, titled like the existing ones:
`[<JIRA-ID>] Cloudsmith Migration - Phase 1 (Pull) - <repo>` or
`... Phase 2 (Push) - <repo>`, with no colon after the bracket. Ask the user
for the Jira ID if you don't have it.

## Sources

- [Maven Repositories](https://hyland.atlassian.net/wiki/spaces/TECH/pages/4303717170/Maven+Repositories):
  what each Cloudsmith repository is for, and which ones pull or push.
- [Cloudsmith Alfresco Consumption](https://hyland.atlassian.net/wiki/spaces/cix/pages/4313722570/Cloudsmith+Alfresco+Consumption):
  OIDC authentication, the Dependabot account and the `maven.cloudsmith.io`
  upload endpoint. It is still a draft.
- [Migrating your CI to the Hyland artifact repository for Alfresco](https://community.hyland.com/discussion/501538/migrating-your-ci-to-the-hyland-artifact-repository-for-alfresco):
  the public guide for customers and community users, with the Activiti
  repositories and the Nexus archive cutover.
