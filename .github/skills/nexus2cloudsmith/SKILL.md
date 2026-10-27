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

The repository roles come from the
[Maven Repositories](https://hyland.atlassian.net/wiki/spaces/TECH/pages/4303717170/Maven+Repositories)
page in Confluence. If you can read it, check it for changes first.

| Nexus | Cloudsmith | Auth |
| --- | --- | --- |
| `nexus/content/groups/public` | `https://artifacts.hyland.dev/public/alfresco-public/maven/` | anonymous |
| Maven Central, public repos | `https://artifacts.hyland.dev/basic/cic-ext-pull-through/maven/` | cloudsmith-auth |
| `nexus/content/groups/internal` | `https://artifacts.hyland.dev/basic/alfresco-internal/maven/` | cloudsmith-auth |
| `nexus/content/repositories/releases`, GA and M versions | `https://artifacts.hyland.dev/basic/alfresco-community-releases/maven/` | cloudsmith-auth |
| `nexus/content/repositories/enterprise-releases`, GA and M versions | `https://artifacts.hyland.dev/basic/alfresco-enterprise-releases/maven/` | cloudsmith-auth |
| any release repository, `-A.x` versions (also internal tools, unreleased products) | `https://artifacts.hyland.dev/basic/alfresco-internal-releases/maven/` | cloudsmith-auth |
| any `*-snapshots` repository | drop it | n/a |

`alfresco-public`, `alfresco-internal` and `cic-ext-pull-through` are pull
only. `alfresco-private` serves customers and partners: never use it in CI.
For a Nexus repository not in this table (thirdparty, for example), stop and
ask the user for the target.

Cloudsmith has no snapshot repositories, by design: mutable artifacts make
builds non-deterministic. Projects release `-A.x` versions instead, on demand
or at most weekly on a schedule, never on every push to master. Remove jobs
that deploy `-SNAPSHOT` versions (for example `publish_snapshot_artifacts`
and its entries in other jobs' `needs:`), and switch a phase that becomes
`deploy` on pushes to master back to `verify`. The `activiti-*-snapshots`
repositories serve another purpose: don't use them.

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
mirror only `central` to `cic-ext-pull-through`. It serves only Central, so
enterprise artifacts can't leak into a community build, and `alfresco-public`
stays anonymous:

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

Prove that `alfresco-public` and Maven Central are enough by resolving with an
empty settings file (see Verify). If something only resolves from
`internal`, stop and tell the user which artifacts. Don't switch to
`alfresco-internal`: the dependency has to be published publicly or dropped.

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
[`cloudsmith-auth`](https://github.com/Alfresco/alfresco-build-tools/blob/master/docs/README.md#cloudsmith-auth) right after
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

Keep one `<repository>` in `distributionManagement`, with the GA URL from the
mapping table, and drop `<snapshotRepository>`:

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
                <url>https://artifacts.hyland.dev/basic/alfresco-internal-releases/maven/</url>
            </repository>
        </distributionManagement>
    </profile>
</profiles>
```

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
- Rename "Nexus" to "Cloudsmith" in job names and comments.
- Turn on the `prerelease` profile for `-A.x` versions. `maven-release-slim`
  does it when `prerelease-profile` is set (its `prerelease-version-marker`
  defaults to `-A.`):

  ```yaml
  - uses: Alfresco/alfresco-build-tools/.github/actions/maven-release-slim@vX.Y.Z
    with:
      release-version: ${{ env.RELEASE_VERSION }}
      prerelease-profile: prerelease
  ```

  If the job runs `mvn deploy` directly, add `-Pprerelease` to that command
  when the version contains `-A.`.

### Docs

Update the README and any docs that mention Nexus. Browse links for the public
repository go to `https://artifacts.hyland.dev/public/alfresco-public/maven/`.

## Rules

- Use the `artifacts.hyland.dev` URLs. Never use raw `cloudsmith.io` URLs.
- Keep repository and server ids neutral: `alfresco-public`,
  `alfresco-internal`, `alfresco-releases`, or the Cloudsmith repository name
  (`cic-ext-pull-through`). Don't put "cloudsmith" in ids, and only name ids
  in comments that exist in the file.
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
git grep -n "artifacts.alfresco.com"

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
`... Phase 2 (Push) - <repo>`. Ask the user for the Jira ID if you don't have
it.
