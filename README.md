# vimhelp.nvim

[![CI](https://github.com/jedi-knights/vimhelp.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/jedi-knights/vimhelp.nvim/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/jedi-knights/vimhelp.nvim?sort=semver)](https://github.com/jedi-knights/vimhelp.nvim/releases/latest)
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
- [`vimhelp-index`](https://github.com/jedi-knights/vimhelp-index) —
  the Rust CLI this plugin shells out to (install below)
- An index built by `vimhelp-index build` (see [Build an index](#build-an-index))

## Install

### 1. Install the `vimhelp-index` CLI

Pick one — all methods land the same signed 5-target binary:

```sh
# Homebrew (macOS, Linux)
brew install jedi-knights/tap/vimhelp-index

# Shell one-liner (macOS, Linux)
curl --proto '=https' --tlsv1.2 -LsSf \
  https://github.com/jedi-knights/vimhelp-index/releases/latest/download/vimhelp-index-installer.sh | sh

# Windows PowerShell
powershell -ExecutionPolicy Bypass -c "irm https://github.com/jedi-knights/vimhelp-index/releases/latest/download/vimhelp-index-installer.ps1 | iex"
```

Or grab a prebuilt archive from the
[releases page](https://github.com/jedi-knights/vimhelp-index/releases/latest)
and drop the binary anywhere on `$PATH`.

### 2. Install the plugin

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "jedi-knights/vimhelp.nvim",
  version = "*",             -- track semver tags; omit to follow main
  cmd = { "VimHelpSearch", "VimHelpHover", "VimHelpBuild" },
  keys = {
    { "K", function() require("vimhelp").hover() end, desc = "vimhelp hover" },
  },
  -- Optional: force a specific picker instead of auto-detecting.
  -- dependencies = { "folke/snacks.nvim" },        -- for snacks picker
  -- dependencies = { "nvim-telescope/telescope.nvim" }, -- for telescope
  opts = {
    -- Defaults are usually right when vimhelp-index is on PATH.
    -- index_dir       = vim.fn.stdpath("cache") .. "/vimhelp-index",
    -- binary_path     = "/opt/homebrew/bin/vimhelp-index",
    -- limit           = 20,
    -- picker          = "auto",  -- "auto" | "snacks" | "telescope" | "messages"
    -- auto_index      = false,
    -- auto_index_docs = vim.env.VIMRUNTIME .. "/doc/*.txt",
  },
}
```

Verify with `:checkhealth vimhelp` — reports whether the CLI is
discoverable and the index directory exists.

## Build an index

You need a built index before search will return anything. Three ways
to get one:

### Auto-build on first use (opt-in)

```lua
require("vimhelp").setup({
  auto_index = true,
  -- Default docs glob covers just built-in Neovim help. Widen with
  -- either a single glob or a list of globs:
  auto_index_docs = {
    vim.env.VIMRUNTIME .. "/doc/*.txt",
    vim.fn.stdpath("data") .. "/lazy/*/doc/*.txt",
  },
})
```

When `auto_index = true` and `index_dir` doesn't exist yet, the next
`:VimHelpSearch` or `:VimHelpHover` transparently builds the index
first (blocking, with a progress `vim.notify`). Off by default — a
long-running subprocess triggered from a search command is a
surprise the user should opt into.

`auto_index_docs` accepts either a single glob string or a list of
glob strings; a list expands into repeated `--docs` flags on the CLI.
Individual list entries that match zero files are silently ignored
(handles the `plugins/*/doc/*.txt` shape on a fresh install); only
an empty union across every glob errors.

### `:VimHelpBuild` — manual build

```
:VimHelpBuild               " full build against auto_index_docs
:VimHelpBuild incremental   " re-index only changed files
```

`:VimHelpBuild` runs asynchronously — the editor stays responsive
while `vimhelp-index` chews through the docs corpus (a full build over
a few thousand help files takes multiple seconds). Progress and the
CLI's summary line surface as `vim.notify` messages. Search stays
functional while a build runs because the tantivy index commits
atomically — a concurrent `:VimHelpSearch` sees the old snapshot xor
the new one, never a torn state.

### Directly via the CLI

Once `vimhelp-index` is installed (see [Install](#1-install-the-vimhelp-index-cli)),
the plugin and the CLI share the same on-disk index — building via the
CLI is equivalent to `:VimHelpBuild`:

```sh
vimhelp-index build --docs "$VIMRUNTIME/doc/*.txt" --out ~/.cache/nvim/vimhelp-index
vimhelp-index build --incremental --docs "$VIMRUNTIME/doc/*.txt" --out ~/.cache/nvim/vimhelp-index
```

## Usage

### `:VimHelpSearch <query>` — interactive search

```
:VimHelpSearch floating window
```

`:VimHelpSearch` opens a picker when one is available:

- **snacks** — picked first when [`folke/snacks.nvim`](https://github.com/folke/snacks.nvim) is loaded
- **telescope** — picked when snacks isn't available but [`nvim-telescope/telescope.nvim`](https://github.com/nvim-telescope/telescope.nvim) is
- **messages** — fallback for bare Neovim, prints ranked hits to `:messages`

Select a hit to jump: `:help <tag>` when the hit has a tag,
`:edit <document>` at the line otherwise.

Force a specific backend with the `picker` config key:
`"auto"` (default), `"snacks"`, `"telescope"`, or `"messages"`.
Non-`"messages"` values silently fall back to `"messages"` when the
requested picker isn't loadable, so `:VimHelpSearch` never errors
just because a peer isn't installed.

Sample messages output (fallback):

```
1. nvim_open_win  (score 3.42)
   $VIMRUNTIME/doc/api.txt:1287  — 3.2. Window functions
   Opens a new floating window. Windows attach to a buffer …

2. wincfg-title  (score 1.85)
   ...
```

### `:VimHelpHover` — jump to the top hit for `<cword>`

```
:VimHelpHover
```

Grabs the word under the cursor, runs a `--limit=1` search, and jumps
straight to the top hit. Skips the picker on purpose — hover is a
one-keystroke "go to the doc" gesture; explore alternatives via
`:VimHelpSearch`.

Bind to `K` (or your preferred key):

```lua
vim.keymap.set("n", "K", require("vimhelp").hover, { desc = "vimhelp hover" })
```

The plugin does NOT auto-map `K` — it's already claimed by LSP hover,
filetype-specific handlers, and user configs, so auto-mapping would be
user-hostile.

Every hover failure mode (no word under cursor, missing binary, missing
index, zero hits, non-zero subprocess exit) surfaces as a `vim.notify`
line, never a Lua traceback. Safe to bind directly.

### Health

Run `:checkhealth vimhelp` to verify the binary and index directory
are resolvable — both surface actionable messages when missing.

## How it works

1. `:VimHelpSearch <query>` runs `vimhelp-index search --index=<configured-dir> --format=json <query>` as a subprocess.
2. Parses the JSON envelope into a Lua table.
3. Dispatches the result to the configured picker backend (`snacks` → `telescope` → `messages` under the `"auto"` default).
4. On selection, jumps to `:help <tag>` when the hit has a tag, else `:edit <document>` at the line.

Every subprocess, picker framework, and jump action is injectable via a `deps` table for tests — nothing spawns a real binary, no real picker gets opened, no cursor gets moved. See `tests/` for the pattern.

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
