# Contributing to Pokessentials

See [BUILDING.md](BUILDING.md) to build and run the game.

## Formatting

Every push and pull request runs a formatting check on the Ruby and JSON files
it changes (`.github/workflows/format.yml`). Run the same check before you push:

```bash
make check-format
```

Fix what can be fixed automatically:

```bash
make format
```

Both look at what changed since `origin/main`, uncommitted changes included.
Compare with another branch with `BASE`, for example `make check-format BASE=origin/dev`.

What is checked (`tools/scripts/check_format.py`):

- **Ruby**: RuboCop's `Layout` cops, with the settings in `.rubocop.yml`, plus
  syntax errors. Only the lines you add or change are checked, so editing an
  older Essentials script doesn't mean reformatting the whole file, and
  `make format` only fixes those lines. Event scripts in `src/tiled/` (written
  by the Tiled tools) and everything in `lib/` are skipped.
- **JSON**: every `.json` file (and Tiled's `.tmj`, `.tsj`, `.tx`, `.world`
  and `.tiled-project` files) must be valid JSON. `src/mkxp.json` may contain
  `//` comments. The JSON in `src/pbs/` and `src/tiled/` must be laid out
  exactly as the tools in `tools/importer` write it, so `make pull-pbs` and
  the Tiled tools never undo a format fix. Other JSON only has to be valid.

RuboCop comes from the `Gemfile`:

```bash
bundle install
```

### Pre-commit hook

To check the staged files on every commit, enable the repository's hooks once
per clone:

```bash
git config core.hooksPath .githooks
```

The hook checks what is staged (not the working tree). If RuboCop isn't
installed it only checks JSON and prints a warning. To skip it for one commit,
use `git commit --no-verify`.

## Automated builds

The game is built for Linux, Windows and Android every week. See
[BUILDING.md](BUILDING.md#automated-builds).
