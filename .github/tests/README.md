# Bash scripts testing

Shell scripts used by composite actions are tested with [Bats](https://bats-core.readthedocs.io/), using these assertion libraries:

- [bats-support](https://github.com/bats-core/bats-support): a shared dependency, no assertions of its own
- [bats-assert](https://github.com/bats-core/bats-assert): `assert_success`, `assert_failure [N]`, `assert_output [--partial|--regexp] TEXT`, `refute_output`, `assert_line`/`refute_line`
- [bats-file](https://github.com/bats-core/bats-file): `assert_file_exist`, `assert_file_contains FILE REGEX`, `assert_file_not_contains`, `assert_dir_exist`, ...

Test files live next to the action they cover, in a `tests/` subfolder (e.g. `.github/actions/<action-name>/tests/*.bats`).

## CI behavior

`test-with-bats.yml` installs bats-core and the libraries above with the `setup-bats` action (a wrapper around [bats-core/bats-action](https://github.com/bats-core/bats-action)), exposes their path as `BATS_LIB_PATH`, then runs `bats -r .` from the repo root, picking up every `*.bats` file automatically.

The bats-core and library versions are pinned in [`bats-versions.yml`](bats-versions.yml), which both the `setup-bats` action and the local installer read. Updatecli opens a PR when a new release comes out.

## Running locally

The libraries above aren't bundled with bats-core, so `bats_load_library` needs `BATS_LIB_PATH` pointing at them. Install bats-core itself with your package manager (for example `brew install bats-core`), then install the libraries at the versions CI uses:

```bash
eval "$(.github/scripts/install-bats-libs.sh)"

bats -r --print-output-on-failure .github/actions/<action-name>/tests
```

The script downloads the pinned release tarballs from GitHub into `~/.local/lib/bats` (no sudo, no package manager) and prints `export BATS_LIB_PATH=...`. Run it again after pulling a version bump; libraries already at the pinned version are skipped. Use `--dest DIR` to install somewhere else.

To make it permanent, add the same `export BATS_LIB_PATH="$HOME/.local/lib/bats"` line to your shell profile.
