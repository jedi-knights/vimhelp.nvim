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
	--- this directory; a future auto-index slice will build into it
	--- on first load.
	--- @type string
	index_dir = vim.fn.stdpath("cache") .. "/vimhelp-index",

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
