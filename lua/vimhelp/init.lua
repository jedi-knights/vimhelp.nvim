--- vimhelp: full-text search over `:help` via the vimhelp-index CLI.
---
--- Public entry points for :VimHelpSearch and :VimHelpHover. Heavy
--- lifting is split across four modules — binary.lua (subprocess
--- invocation, injectable), search.lua (pure JSON parsing + rendering),
--- picker.lua (dispatcher over snacks/telescope/messages backends),
--- jump.lua (land the cursor on a selected hit). This module is a thin
--- facade — those four seams are the test surface.

local binary = require("vimhelp.binary")
local config = require("vimhelp.config")
local detector = require("vimhelp.detector")
local jump = require("vimhelp.jump")
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

--- K-handler: grab the word under the cursor, run search --limit=1,
--- and jump straight to the top hit. Skips the picker on purpose —
--- K is a one-keystroke "go to the doc" gesture; users who want to
--- explore alternatives use :VimHelpSearch.
---
--- Safe to bind directly to a keymap: every failure mode surfaces as
--- a vim.notify line, never as a Lua traceback. This is what
--- distinguishes hover from M.search — search() is a library facade
--- (throws; command wrapper pcalls); hover() is a keymap target
--- (self-contained error handling).
---
--- @param deps table?  { word_getter, notify, runner, jump }
--- @return table?  the parsed { query, hits } when a jump happened;
---                  nil otherwise (empty word / no hits / errored).
function M.hover(deps)
	deps = deps or {}
	local get_word = deps.word_getter or function()
		return vim.fn.expand("<cword>")
	end
	local notify = deps.notify or vim.notify
	local do_jump = deps.jump or jump.to_hit

	local word = get_word()
	if type(word) ~= "string" or word == "" then
		notify("vimhelp: no word under cursor", vim.log.levels.INFO)
		return nil
	end

	local bin = binary.resolve(M.config.binary_path)
	if not bin then
		notify(
			"vimhelp: vimhelp-index binary not found. "
				.. "Install from https://github.com/jedi-knights/vimhelp-index/releases "
				.. "or set require('vimhelp').setup({ binary_path = '<path>' })",
			vim.log.levels.ERROR
		)
		return nil
	end
	if vim.fn.isdirectory(M.config.index_dir) ~= 1 then
		notify(
			string.format(
				"vimhelp: index directory %q does not exist. "
					.. "Build it first: vimhelp-index build --docs='<glob>' --out=%q",
				M.config.index_dir,
				M.config.index_dir
			),
			vim.log.levels.ERROR
		)
		return nil
	end

	-- Fixed limit=1 for hover, independent of M.config.limit — hover's
	-- contract is "one keystroke to the doc." Users who want a ranked
	-- list use :VimHelpSearch.
	local result = binary.search(bin, M.config.index_dir, word, 1, deps)
	if result.code ~= 0 then
		notify(
			string.format("vimhelp: vimhelp-index exited with code %d — %s", result.code, result.stderr),
			vim.log.levels.ERROR
		)
		return nil
	end

	local parsed = search.parse(result.stdout)
	if #parsed.hits == 0 then
		notify(string.format("vimhelp: no hits for %q", word), vim.log.levels.INFO)
		return nil
	end

	do_jump(parsed.hits[1])
	return parsed
end

return M
