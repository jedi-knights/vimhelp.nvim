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

--- Run `vimhelp-index build` against the configured index_dir + docs
--- glob, notifying progress and result. Same subprocess model as
--- search — deps.runner is injectable for tests.
---
--- `opts.incremental = true` passes `--incremental` to the CLI. The
--- :VimHelpBuild command exposes this via its `incremental` argument.
---
--- @param opts table?  { incremental: boolean }
--- @param deps table?  { runner, notify }
--- @return boolean  true when the build succeeded; false when it didn't
---                   (failure was already notified with the specific reason).
function M.build(opts, deps)
	opts = opts or {}
	deps = deps or {}
	local notify = deps.notify or vim.notify

	local bin = binary.resolve(M.config.binary_path)
	if not bin then
		notify(
			"vimhelp: vimhelp-index binary not found. "
				.. "Install from https://github.com/jedi-knights/vimhelp-index/releases",
			vim.log.levels.ERROR
		)
		return false
	end

	notify(string.format("vimhelp: building index at %s...", M.config.index_dir), vim.log.levels.INFO)
	local result = binary.build(bin, M.config.auto_index_docs, M.config.index_dir, opts, deps)
	if result.code ~= 0 then
		notify(
			string.format("vimhelp: build failed (exit %d): %s", result.code, vim.trim(result.stderr or "")),
			vim.log.levels.ERROR
		)
		return false
	end
	local trimmed = vim.trim(result.stdout or "")
	if trimmed ~= "" then
		-- CLI's own summary line — "Indexed N section(s) from M file(s) → ...".
		notify(trimmed, vim.log.levels.INFO)
	else
		notify("vimhelp: build complete.", vim.log.levels.INFO)
	end
	return true
end

--- Confirm the index directory is usable. When it isn't AND
--- `auto_index = true`, transparently build it first.
---
--- Returns nil on success (index ready to search), an error MESSAGE
--- STRING on failure. Callers decide how to surface the failure —
--- `M.search` throws (caught by the :VimHelpSearch command wrapper);
--- `M.hover` notifies. Keeping the return shape uniform means
--- neither caller has to pcall the other's contract.
---
--- @param deps table?  { runner, notify }
--- @return string?  nil on success, error message on failure
function M.ensure_index(deps)
	if vim.fn.isdirectory(M.config.index_dir) == 1 then
		return nil
	end
	if not M.config.auto_index then
		return string.format(
			"vimhelp: index directory %q does not exist. "
				.. "Run :VimHelpBuild, or set require('vimhelp').setup({ auto_index = true }) "
				.. "to have it built automatically on first use.",
			M.config.index_dir
		)
	end
	if not M.build({}, deps) then
		-- M.build already notified the specific reason; hand the caller
		-- a short handle so the search/hover surface has something to
		-- throw / notify without duplicating the detail.
		return "vimhelp: auto-build failed — see :messages for the specific error"
	end
	return nil
end

--- Search the vimhelp index and route the result to a picker backend.
--- On bare Neovim (no snacks / telescope) falls back to printing to
--- :messages, matching the pre-picker behaviour.
---
--- Returns the raw parsed result so callers can pipe it further.
---
--- @param query string  Non-empty query text. Multi-word queries work
---                       — clap passes them through as a single arg.
--- @param deps table?   { runner, has_module, pickers, snacks, telescope, jump, printer, notify }
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

	local index_err = M.ensure_index(deps)
	if index_err then
		error(index_err)
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

	-- ensure_index returns nil on success. Uses same deps shape so a
	-- test-injected runner covers both search and the auto-build.
	local index_err = M.ensure_index(deps)
	if index_err then
		notify(index_err, vim.log.levels.ERROR)
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
