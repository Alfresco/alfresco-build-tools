# Security best practices

Before creating / modifying any GitHub Actions workflow make sure you're familiar with . Pay special attention to:

- [Security hardening for GitHub Actions](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions)
  - [Script injections](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions#understanding-the-risk-of-script-injections)
  - [third-party/community actions](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions#using-third-party-actions)
- [Keeping your GitHub Actions and workflows secure](https://securitylab.github.com/research/github-actions-preventing-pwn-requests/)
  - [Part 2: Untrusted input](https://securitylab.github.com/research/github-actions-untrusted-input/)

In this page we are also providing guidance on how to setup common tooling related to security.

- [Security best practices](#security-best-practices)
  - [Secrets detection](#secrets-detection)
    - [First setup](#first-setup)
    - [Updating new/old secrets to the baseline](#updating-newold-secrets-to-the-baseline)
      - [Excluding multiple secrets via regex](#excluding-multiple-secrets-via-regex)

## Secrets detection

It is far too easy to accidentally leak secrets on public repositories by
inadvertently committing them in variables or configuration files after just
doing a quick test during development.

To prevent this kind of issues, it's highly suggested to integrate a solution
like [Yelp/detect-secrets](https://github.com/Yelp/detect-secrets) in the
standard development workflow.

### First setup

As a prerequisite,
[install](https://github.com/Yelp/detect-secrets#installation) the
`detect-secrets` CLI.

The first step is to create the secrets baseline, that is just a JSON file
holding all the settings and references all the potential secrets that have been
detected in your codebase with:

```sh
detect-secrets scan > .secrets.baseline
git add .secrets.baseline
```

Then you can start auditing all the detected secrets in your codebase with:

```sh
detect-secrets audit .secrets.baseline
```

For each detected secret, it will ask you if that secret is really meant to be
present in the codebase or not:

- Replying with Yes, will whitelist that entry as a non-secret (`is_secret`
  field will be `false`)
- Replying with No, will mark that entry as a secret that is meant to be removed
  in the future (`is_secret` field will be `true`)
- Replying with Skip, will skip to the next secret without marking the current
  secret (will ask what to do again on the next audit)

> Marking each detection as a secret or not is just to make everyone aware that
> a secret is meant to be there or if an issue that needs to be solved. If you
> have many non-secrets that get detected but follows a certain pattern, read
> the [exclusion via regex section](#excluding-multiple-secrets-via-regex)
> before proceeding.

At this point you can commit the baseline:

```sh
git add .secrets.baseline
git commit -m 'detect-secrets baseline initialized'
```

Last step is to enable the `pre-commit` hook in your `.pre-commit-config.yaml`
that will warn when one or more secrets not already present in the baseline are
detected:

```yaml
  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.4.0
    hooks:
      - id: detect-secrets
        args: ["--baseline", ".secrets.baseline"]
```

### Updating new/old secrets to the baseline

To update the current baseline with any new secret or to automatically remove
the ones not anymore present:

```sh
detect-secrets scan --baseline .secrets.baseline
```

> if you have recently updated detect-secrets, you may want to opt-in for new
> plugins with `--force-use-all-plugins`

Run a diff to make sure that everything you expect is there and proceed with
auditing and finally committing the update:

```sh
git diff
detect-secrets audit .secrets.baseline
git add .secrets.baseline
git commit -m 'detect-secrets baseline updated'
```

#### Excluding multiple secrets via regex

It's possible to provide to `detect-secrets scan` different exclude
regex patterns if you have a lot of false positive that you don't want to
handle on an individual basis:

```sh
  --exclude-lines EXCLUDE_LINES
                        If lines match this regex, it will be ignored.
  --exclude-files EXCLUDE_FILES
                        If filenames match this regex, it will be ignored.
  --exclude-secrets EXCLUDE_SECRETS
                        If secrets match this regex, it will be ignored.
```

For example, to exclude all files with xyz extension or which path is inside a
`node_modules` folder:

```sh
detect-secrets scan --baseline .secrets.baseline --exclude-files '.*\.yml' --exclude-files 'node_modules'
```

For example, to exclude a dummy/default password that is ok to use:

```sh
detect-secrets scan --baseline .secrets.baseline --exclude-secrets 'MyDefaultPassword'
```

You can check if exclusion are working as expected by inspecting the resulting
baseline that should not have anymore references to secrets that are matching
at least one exclusion regex.

```sh
git diff
git add .secrets.baseline
git commit -m 'Excluding unwanted files in the baseline'
```

Please also note that when those options are present, they overwrite any
previously defined exclusion of the same type in the baseline, i.e. if you want
to append an exclusion pattern you need to manually specify again all of them
when running `detect-secrets scan`.
