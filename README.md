# vimhelp.nvim

[![CI](https://github.com/jedi-knights/vimhelp.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/jedi-knights/vimhelp.nvim/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

You know the docs are in there somewhere. You remember it was about
floating windows, or was it popups? `:helpgrep` returns nine screens of
noise. `:help nvim_open_win` works only if you already know the tag.

`vimhelp.nvim` wires [`vimhelp-index`](https://github.com/jedi-knights/vimhelp-index)
into Neovim: full-text search over `:help` that finds the doc you need
without knowing the exact tag. Thin shim — the plugin invokes the CLI
as a subprocess and renders the JSON response; heavy lifting (tantivy
index, BM25 scoring, snippet highlighting) lives in the binary.

**Requirements:**
- Neovim 0.10+
- The [`vimhelp-index`](https://github.com/jedi-knights/vimhelp-index)
  binary on `$PATH` (or set `binary_path` in setup)
- An index built by `vimhelp-index build` (see below)

**Status:** pre-v0.1.0. `:VimHelpSearch` works today; a snacks/telescope
picker, `K`-handler for enhanced hover, and an auto-index bootstrap
land in follow-up slices.

## Install

### With lazy.nvim

```lua
{
  "jedi-knights/vimhelp.nvim",
  cmd = "VimHelpSearch",
  opts = {
    -- Optional. Defaults are usually right when vimhelp-index is on PATH.
    -- index_dir = vim.fn.stdpath("cache") .. "/vimhelp-index",
    -- binary_path = "/opt/homebrew/bin/vimhelp-index",
    -- limit = 20,
  },
}
```

## Build an index

The plugin doesn't build the index for you (auto-index is a follow-up
slice). Build once before first use:

```sh
brew install jedi-knights/tap/vimhelp-index
vimhelp-index build --docs "$VIMRUNTIME/doc/*.txt" --out ~/.cache/nvim/vimhelp-index
```

Re-run with `--incremental` when your runtime changes:

```sh
vimhelp-index build --incremental --docs "$VIMRUNTIME/doc/*.txt" --out ~/.cache/nvim/vimhelp-index
```

## Usage

```
:VimHelpSearch floating window
```

Sample output:

```
1. nvim_open_win  (score 3.42)
   $VIMRUNTIME/doc/api.txt:1287  — 3.2. Window functions
   Opens a new floating window. Windows attach to a buffer …

2. wincfg-title  (score 1.85)
   ...
```

Run `:checkhealth vimhelp` to verify the binary and index directory
are resolvable — both surface actionable messages when missing.

## How it works

1. `:VimHelpSearch <query>` runs `vimhelp-index search --index=<configured-dir> --format=json <query>` as a subprocess.
2. Parses the JSON envelope into a Lua table.
3. Renders hits ranked by BM25 score with snippets centered on the matched term.

The subprocess runner is injectable via `require("vimhelp").search(query, { runner = ... })` so tests never spawn a real binary. See `tests/` for the pattern.

## Development

```sh
make lint    # stylua --check .
make test    # plenary-busted headless
```

## Related

- [`vimhelp-index`](https://github.com/jedi-knights/vimhelp-index) — the Rust CLI this plugin shells out to.
- [`plug-audit`](https://github.com/jedi-knights/plug-audit) — sibling tool that lints Neovim plugin repos statically. Different problem (repo hygiene vs. runtime search), same jedi-knights toolchain.

## License

MIT. See [LICENSE](./LICENSE).
