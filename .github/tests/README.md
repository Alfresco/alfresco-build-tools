# Bash scripts testing

Shell scripts used by composite actions are tested with [Bats](https://bats-core.readthedocs.io/), using [bats-support](https://github.com/bats-core/bats-support), [bats-assert](https://github.com/bats-core/bats-assert) and [bats-file](https://github.com/bats-core/bats-file) for assertions (`assert_success`, `assert_failure`, `assert_output`, `assert_file_contains`, ...). Test files live next to the action they cover, in a `tests/` subfolder (e.g. `.github/actions/<action-name>/tests/*.bats`).

## CI behavior

`test-with-bats.yml` installs bats-core and the libraries above via [bats-core/bats-action](https://github.com/bats-core/bats-action), exposes their path as `BATS_LIB_PATH`, then runs `bats -r .` from the repo root, picking up every `*.bats` file automatically.

## Running locally

The libraries above aren't bundled with bats-core, so `bats_load_library` needs `BATS_LIB_PATH` pointing at them.

With Homebrew, via the [`kaos/shell`](https://github.com/kaos/homebrew-shell) tap (bats-support comes along as a dependency):

```bash
brew tap kaos/shell
brew install bats-assert bats-file
export BATS_LIB_PATH="$(brew --prefix)/lib"

bats -r --print-output-on-failure .github/actions/<action-name>/tests
```

Homebrew treats third-party taps as untrusted by default; if `brew install` refuses to load the formulae, run `brew trust kaos/shell` first.

Without Homebrew (or to match the exact versions CI uses), clone the libraries instead:

```bash
BATS_LIB_PATH="$HOME/.local/lib/bats"
mkdir -p "$BATS_LIB_PATH"
for lib in bats-support bats-assert bats-file; do
  git clone --depth 1 "https://github.com/bats-core/$lib" "$BATS_LIB_PATH/$lib"
done
export BATS_LIB_PATH
```
