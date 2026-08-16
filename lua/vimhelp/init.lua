--- vimhelp: full-text search over `:help` via the vimhelp-index CLI.
---
--- Public entry point for the :VimHelpSearch command. Heavy lifting
--- is split across four modules — binary.lua (subprocess invocation,
--- injectable), search.lua (pure JSON parsing + rendering), picker.lua
--- (dispatcher over snacks/telescope/messages backends), jump.lua
--- (land the cursor on a selected hit). This module is a thin facade —
--- those four seams are the test surface.

local binary = require("vimhelp.binary")
local config = require("vimhelp.config")
local detector = require("vimhelp.detector")
local picker = require("vimhelp.picker")
local search = require("vimhelp.search")

local M = {}

--- Merged config, populated on first setup() or on first command use.
--- Defaults ship in config.lua; callers override via setup({...}).
M.config = config.merge({})

--- Set up the plugin. Safe to call multiple times; last call wins.
--- Optional — the plugin loads its `plugin/` entry on startup and
--- picks up defaults; setup() is only needed for overrides.
--- @param opts table? User-supplied config; merged over defaults.
--- @param deps table? Injected dependencies. Tests pass fakes here.
function M.setup(opts, deps)
	if not detector.should_load() then
		return
	end
	M.config = config.merge(opts or {})
	M.deps = deps or {}
end

--- Search the vimhelp index and route the result to a picker backend.
--- On bare Neovim (no snacks / telescope) falls back to printing to
--- :messages, matching the pre-picker behaviour.
---
--- Returns the raw parsed result so callers can pipe it further
--- (a future `K`-handler slice will call this and consume `.hits[1]`
--- without opening a picker).
---
--- @param query string  Non-empty query text. Multi-word queries work
---                       — clap passes them through as a single arg.
--- @param deps table?   { runner, has_module, pickers, snacks, telescope, jump, printer }
--- @return { query: string, hits: table[] }?
function M.search(query, deps)
	assert(type(query) == "string" and #query > 0, "vimhelp.search: query required")
	local bin = binary.resolve(M.config.binary_path)
	if not bin then
		error(
			"vimhelp: vimhelp-index binary not found. "
				.. "Install from https://github.com/jedi-knights/vimhelp-index/releases "
				.. "or set require('vimhelp').setup({ binary_path = '/path/to/vimhelp-index' })"
		)
	end
	if vim.fn.isdirectory(M.config.index_dir) ~= 1 then
		error(
			string.format(
				"vimhelp: index directory %q does not exist. Build it first: "
					.. "vimhelp-index build --docs='<glob>' --out=%q",
				M.config.index_dir,
				M.config.index_dir
			)
		)
	end

	local result = binary.search(bin, M.config.index_dir, query, M.config.limit, deps)

	if result.code ~= 0 then
		error(string.format("vimhelp: vimhelp-index exited with code %d — stderr:\n%s", result.code, result.stderr))
	end

	local parsed = search.parse(result.stdout)
	-- Route to picker (or messages fallback). Same deps table so tests
	-- inject fake pickers / has_module through one shape.
	picker.pick(parsed, { picker = M.config.picker }, deps)
	return parsed
end

return M
