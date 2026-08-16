--- Default configuration and merge logic for vimhelp.

local M = {}

M.defaults = {
	--- Path to the vimhelp-index binary. When nil, we look on `$PATH`
	--- via `vim.fn.executable("vimhelp-index")`. Set to an explicit
	--- path to bypass PATH lookup — useful when the binary lives
	--- somewhere non-standard (e.g. cargo install target dir).
	--- @type string?
	binary_path = nil,

	--- Directory where the tantivy index lives. `:VimHelpSearch` opens
	--- this directory; `auto_index = true` builds into it on first use.
	--- @type string
	index_dir = vim.fn.stdpath("cache") .. "/vimhelp-index",

	--- When true, `:VimHelpSearch` / `:VimHelpHover` transparently
	--- build the index on first use if `index_dir` doesn't exist yet.
	--- Off by default: a long-running subprocess triggered from a
	--- search command is a surprise the user should opt into.
	--- @type boolean
	auto_index = false,

	--- Glob(s) passed to `vimhelp-index build` when the auto-build
	--- fires. Accepts a single string OR a list of strings; a list
	--- expands into repeated `--docs` flags. Default covers just
	--- built-in Neovim help. LazyVim users typically widen it to
	--- catch installed plugin docs too:
	---   auto_index_docs = {
	---     vim.env.VIMRUNTIME .. "/doc/*.txt",
	---     vim.fn.stdpath("data") .. "/lazy/*/doc/*.txt",
	---   }
	--- Individual list entries that match zero files are silently
	--- ignored by the CLI; only an empty union across ALL globs errors.
	--- @type string | string[]
	auto_index_docs = (vim.env.VIMRUNTIME or "") .. "/doc/*.txt",

	--- Max hits `:VimHelpSearch` requests from the CLI. Zero means the
	--- CLI's default (currently 20 per the search subcommand). Do not
	--- interpret zero as "unbounded" — every downstream iteration
	--- needs a provable upper bound.
	--- @type integer
	limit = 20,

	--- Which picker backend to open on `:VimHelpSearch`.
	---   "auto"      — snacks if loadable, else telescope, else messages
	---   "snacks"    — force snacks (falls back to messages if unavailable)
	---   "telescope" — force telescope (falls back to messages if unavailable)
	---   "messages"  — always print to :messages (no interactive selection)
	--- @type string
	picker = "auto",
}

--- Deep-merge user opts over defaults. User values win on conflict.
--- @param opts table
--- @return table
function M.merge(opts)
	return vim.tbl_deep_extend("force", {}, M.defaults, opts)
end

return M
