---
name: nexus2cloudsmith
description: "Migrate a Maven repository's CI from the Alfresco Nexus (artifacts.alfresco.com) to Cloudsmith (artifacts.hyland.dev), for pulling dependencies (Phase 1) and deploying releases (Phase 2). Use when: replacing artifacts.alfresco.com URLs in pom.xml or settings.xml; swapping NEXUS_USERNAME/NEXUS_PASSWORD secrets for the cloudsmith-auth OIDC action; moving distributionManagement to Cloudsmith; working on a 'Cloudsmith Migration - Phase 1 (Pull)' or 'Phase 2 (Push)' ticket."
---

# Migrate Maven CI from Nexus to Cloudsmith

## When to Use

- `pom.xml`, `.ci.settings.xml` or a workflow still points at `artifacts.alfresco.com/nexus`
- Workflows pass `secrets.NEXUS_USERNAME` / `secrets.NEXUS_PASSWORD` to Maven
- A Jira ticket asks for "Cloudsmith Migration - Phase 1 (Pull)" or "Phase 2 (Push)"

The migration has two phases, usually one PR each:

1. **Pull**: resolve dependencies and plugins from Cloudsmith.
2. **Push**: deploy release artifacts to Cloudsmith.

Do only the phase the user asked for. If they didn't say, check which one is
already done and do the next one.

## Step 0: Survey the repo

```bash
grep -rn -i -E "artifacts\.alfresco\.com|nexus|MAVEN_USERNAME|MAVEN_PASSWORD" \
  --include=pom.xml --include="*settings*.xml" --include="*.yml" --include="*.yaml" --include="*.md" .
```

Then check the GitHub repository visibility, because that drives both phases:

```bash
gh repo view --json visibility --jq .visibility
```

- **`PUBLIC`**: Alfresco artifacts must come from the anonymous
  `alfresco-public` repository, even if the repo uses the Nexus `internal`
  group today. Many public repos do so only because nobody cleaned it up.
  Follow the public path in Phase 1 instead of copying the existing setup.
- **`PRIVATE` / `INTERNAL`**: builds can resolve from the `internal` group
  with credentials. Follow the internal path in Phase 1.

### Check the Cloudsmith workspace

If the `cloudsmith` CLI is installed and logged in (`cloudsmith whoami`), use
it to confirm the targets below still exist before relying on the table:

```bash
# Repositories in the workspace (the namespace is "hyland")
cloudsmith list repos hyland --page-size 500

# Whether an artifact is available in a repository. "display_source: upstream"
# means Cloudsmith proxied it from an upstream such as Maven Central.
cloudsmith list pkgs hyland/alfresco-internal -q "name:<artifactId>" -F json
```

If a repository the migration needs is missing from the list, stop and tell
the user. Don't point a pom at it.
Without the CLI, use the table as is.

## URL mapping

The repository roles come from the
[Maven Repositories](https://hyland.atlassian.net/wiki/spaces/TECH/pages/4303717170/Maven+Repositories)
page in Confluence. If you can read it, check it for changes first.

| Nexus | Cloudsmith | Auth |
| --- | --- | --- |
| `nexus/content/groups/public` | `https://artifacts.hyland.dev/public/alfresco-public/maven/` | anonymous |
| Maven Central, public repos | `https://artifacts.hyland.dev/basic/cic-ext-pull-through/maven/` | cloudsmith-auth |
| `nexus/content/groups/public-snapshots` | remove it | n/a |
| `nexus/content/groups/internal` | `https://artifacts.hyland.dev/basic/alfresco-internal/maven/` | cloudsmith-auth |
| `nexus/content/repositories/releases`, GA and M versions | `https://artifacts.hyland.dev/basic/alfresco-community-releases/maven/` | cloudsmith-auth |
| `nexus/content/repositories/enterprise-releases`, GA and M versions | `https://artifacts.hyland.dev/basic/alfresco-enterprise-releases/maven/` | cloudsmith-auth |
| any release repository, `-A.x` versions | `https://artifacts.hyland.dev/basic/alfresco-internal-releases/maven/` | cloudsmith-auth |
| any `*-snapshots` deploy repository | none: drop it | n/a |

Push targets:

- GA and M releases go to `alfresco-community-releases` (community repos) or
  `alfresco-enterprise-releases` (enterprise repos).
- Every `-A.x` release goes to `alfresco-internal-releases`, community or
  enterprise, along with internal tools and unreleased products.

`alfresco-public`, `alfresco-internal` and `cic-ext-pull-through` are pull
only. `alfresco-private` serves customers and partners: never use it in CI.

If the repo uses a Nexus repository that is not in this table (thirdparty,
for example), stop and ask the user for the target. Don't guess one.

Cloudsmith has no snapshot repositories, by design: mutable artifacts make
builds non-deterministic. Projects publish `-A.x` versions instead of
`-SNAPSHOT`, on demand or at most weekly on a schedule. Never release on
every push to master, so don't turn a snapshot job into an `-A.x` release.
Once `<snapshotRepository>` is gone, any `mvn deploy` of a
`-SNAPSHOT` version fails, so remove jobs that do this (for example a
`publish_snapshot_artifacts` job and its entries in other jobs' `needs:`), and
switch a phase that becomes `deploy` on pushes to master back to `verify`.
Don't point `<snapshotRepository>` at a Cloudsmith repository: the
`activiti-*-snapshots` ones serve another purpose.

Binary downloads from `nexus.alfresco.com/nexus/service/local/...` (in
Dockerfiles or CI scripts) are not Maven resolution and are out of scope.
Leave them and mention them to the user.

## Phase 1: Pull

### Public repo

In `pom.xml`, change the `alfresco-public` `<repository>` and
`<pluginRepository>` URLs (add them if the repo relied on a settings-file
profile or mirror instead), and delete the public snapshots repository:

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

Put Maven Central first in `<pluginRepositories>`. The public
`alfresco-public` repository doesn't proxy Central, so asking it first for
every plugin slows the build down:

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
files, and drop the `NEXUS_*` env from build jobs.

Maven Central comes through the private `cic-ext-pull-through` proxy, not
`alfresco-internal`: it serves only Central, so enterprise artifacts can't
leak into a community build. `.ci.settings.xml` mirrors only `central`, so
`alfresco-public` stays anonymous:

```xml
<settings>
    <mirrors>
        <mirror>
            <id>cic-ext-pull-through</id>
            <name>Maven Central through Cloudsmith</name>
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

In the workflows, grant `id-token: write` and add `cloudsmith-auth` after
`setup-java-build` in every job that runs Maven, as in the private path below.

Prove that `alfresco-public` and Maven Central are enough by resolving with an
empty settings file (see Verify). If something only resolves from
`internal`, stop and tell the user which artifacts. Don't switch to
`alfresco-internal`: the dependency has to be published publicly or dropped.

### Private / internal repo

In `.ci.settings.xml`, replace the `alfresco-internal` profile and its
repositories with a single mirror, and point its server at the Cloudsmith
credentials:

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

`mirrorOf *` is fine here: the `alfresco-internal` repository proxies Maven
Central.

The mirror overrides any repositories declared in `pom.xml` during CI, but
local builds still use them. Apply the URL mapping table to every
`<repository>` and `<pluginRepository>` in the poms that still points at
`artifacts.alfresco.com`, and delete the snapshot-only ones.

Remove `<server>` entries whose repository no longer exists (the other
internal, public and thirdparty ids). Keep the deploy servers that still use
`MAVEN_USERNAME` / `MAVEN_PASSWORD`, because Phase 2 replaces those.

In the workflows, grant `id-token: write` and add `cloudsmith-auth` right after
`setup-java-build` in **every** job that runs Maven, including
`dependency-graph.yml`:

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: Alfresco/alfresco-build-tools/.github/actions/setup-java-build@vX.Y.Z
  - uses: Alfresco/alfresco-build-tools/.github/actions/cloudsmith-auth@vX.Y.Z
    with:
      oidc-namespace: ${{ vars.CLOUDSMITH_NAMESPACE }}
```

If the build also pulls from a repository that Cloudsmith doesn't proxy (GitHub
Packages, for example), exclude its id from the mirror:
`<mirrorOf>*,!github</mirrorOf>`.

### Both

In `dependency-graph.yml`, drop the `maven-username` / `maven-password` inputs
fed from `NEXUS_*` secrets on `maven-dependency-scan`. They only set
`MAVEN_USERNAME` / `MAVEN_PASSWORD`, which the settings no longer read.

If `.github/dependabot.yml` declares a Nexus `maven-repository` registry,
point it at the same Cloudsmith repository as the build. Dependabot can't use
OIDC and only expands Dependabot secrets (not `vars`), so it uses two
Dependabot secrets that must exist in the repo or org:

```yaml
registries:
  maven-alfresco-internal:
    type: maven-repository
    url: https://artifacts.hyland.dev/basic/alfresco-internal/maven/
    username: ${{ secrets.DEPENDABOT_CLOUDSMITH_USERNAME }}
    password: ${{ secrets.DEPENDABOT_CLOUDSMITH_API_KEY }}
```

Keep the registry name so the `registries:` entries under each update still
match. In a public repo, point the registry at
`https://artifacts.hyland.dev/public/alfresco-public/maven/` instead and drop
`username` / `password`.

## Phase 2: Push

### `pom.xml`

Keep one `<repository>` in `distributionManagement` and drop
`<snapshotRepository>`. Pick the URL from the mapping table:

```xml
<distributionManagement>
    <repository>
        <id>alfresco-releases</id>
        <name>Alfresco Community Releases</name>
        <url>https://artifacts.hyland.dev/basic/alfresco-community-releases/maven/</url>
    </repository>
</distributionManagement>
```

For an enterprise repo, use `Alfresco Enterprise Releases` and the
`alfresco-enterprise-releases` URL. In both cases `-A.x` releases go to
`alfresco-internal-releases` instead: see "Release workflow" below.

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

- Grant `id-token: write` to the release job.
- Add the `cloudsmith-auth` step after `setup-java-build`, as in Phase 1, if
  the job doesn't have it yet.
- Remove `MAVEN_USERNAME: ${{ secrets.NEXUS_USERNAME }}` and
  `MAVEN_PASSWORD: ${{ secrets.NEXUS_PASSWORD }}`, whether they sit at job or
  workflow level. Check that nothing else still reads them first.
- Rename "Nexus" to "Cloudsmith" in job names and comments.
- Send `-A.x` releases to `alfresco-internal-releases`
  by overriding the deploy target when the version contains `-A.`. It reuses
  the `alfresco-releases` server, so no new credentials are needed:

  ```yaml
  - uses: Alfresco/alfresco-build-tools/.github/actions/maven-release-slim@vX.Y.Z
    with:
      release-version: ${{ env.RELEASE_VERSION }}
      maven-args: >-
        -DskipTests
        ${{ contains(env.RELEASE_VERSION, '-A.') && '-DaltReleaseDeploymentRepository=alfresco-releases::https://artifacts.hyland.dev/basic/alfresco-internal-releases/maven/' || '' }}
  ```

  The `id::url` form needs maven-deploy-plugin 3.x. With 2.x, use
  `alfresco-releases::default::<url>`. If the job runs `mvn deploy` directly,
  add the same property to that command.

### Docs

Update the README and any docs that mention Nexus. Browse links for the public
repository go to `https://artifacts.hyland.dev/public/alfresco-public/maven/`.

## Rules

- Use the `artifacts.hyland.dev` URLs. Never use raw `cloudsmith.io` URLs.
- Keep repository and server ids neutral: `alfresco-public`,
  `alfresco-internal`, `alfresco-releases`, or the Cloudsmith repository name
  (`cic-ext-pull-through`). Don't put "cloudsmith" in ids.
- Comments must name ids that actually exist in the file.
- Pin `cloudsmith-auth` to a release tag (`@vX.Y.Z`). alfresco-build-tools
  releases are immutable, so a tag is as safe as a SHA. If the repo already pins
  build-tools actions by SHA, a full 40-character SHA with a `# vX.Y.Z` comment
  is fine too. Use the same ref as the repo's other build-tools actions when
  that ref already has `cloudsmith-auth`. Otherwise use the latest release:
  `gh api repos/Alfresco/alfresco-build-tools/releases/latest --jq .tag_name`.
- Reference `CLOUDSMITH_USERNAME` / `CLOUDSMITH_API_KEY` only as
  `${env.…}` in settings files or `$VAR` in shell. Never as `${{ }}`.
- `cloudsmith-auth` needs `id-token: write` on the calling job, or the token
  request fails.

## Verify

```bash
# No Nexus left
grep -rn "artifacts.alfresco.com" . --exclude-dir=.git

# Public repos: resolves with no credentials and an empty local repository
echo '<settings/>' > "${TMPDIR:-/tmp}/empty-settings.xml"
mvn -B -s "${TMPDIR:-/tmp}/empty-settings.xml" \
  -Dmaven.repo.local="$(mktemp -d)" dependency:go-offline
```

The fresh local repository matters: a warm `~/.m2` hides artifacts that only
came from an authenticated repository.

For private repos, the build can only be checked in CI because it needs the
OIDC token. Run pre-commit (and `actionlint` if the repo uses it) before
pushing.

## PR

Open one PR per phase, titled like the existing ones:
`[<JIRA-ID>] Cloudsmith Migration - Phase 1 (Pull) - <repo>` or
`... Phase 2 (Push) - <repo>`. Ask the user for the Jira ID if you don't have
it.
