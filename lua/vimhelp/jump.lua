--- Jump to a selected search hit.
---
--- Split from picker adapters so every backend (snacks, telescope, the
--- messages fallback) invokes the same landing behaviour. Pure via
--- injectable `cmd` + `cursor` seams so tests never touch the real
--- editor.

local M = {}

--- Land the cursor on the requested hit.
---
--- Preference order:
---   1. `hit.tag` non-empty → try `:help <tag>` first. Nicer UX when
---      the tag is discoverable in Neovim's runtimepath (help syntax,
---      folds, `[[` navigation). On failure — most commonly E149 when
---      the indexed corpus lives outside the runtime — falls through
---      to (2) instead of throwing.
---   2. `hit.document` non-empty → `:edit <document>` + optionally
---      set cursor to `hit.line`.
---
--- The two-step fallback matters: an index built from
--- `$VIMRUNTIME/doc/*.txt` resolves via `:help`, but an index built
--- from an arbitrary directory of vimdoc-format text (a plugin repo,
--- a snapshot corpus) won't — and we should still land the user on
--- the right line, just via `:edit` instead of `:help`.
---
--- `hit.line` is 1-indexed to match Vim's own line numbering.
---
--- @param hit table  { tag: string?, document: string?, line: integer? }
--- @param deps table? { cmd: fun(cmd: string), cursor: fun(win, {row, col}) }
function M.to_hit(hit, deps)
	assert(type(hit) == "table", "jump.to_hit: hit must be a table")
	deps = deps or {}
	local cmd = deps.cmd or vim.cmd
	local cursor = deps.cursor or vim.api.nvim_win_set_cursor

	if type(hit.tag) == "string" and #hit.tag > 0 then
		-- fnameescape guards against spaces in the tag; help tags rarely
		-- have them but defence-in-depth here is cheap.
		local ok = pcall(cmd, "help " .. vim.fn.fnameescape(hit.tag))
		if ok then
			return
		end
		-- :help failed (typical: E149 no help for <tag>). Fall through
		-- to the document/line path so the user still lands somewhere.
	end

	if type(hit.document) == "string" and #hit.document > 0 then
		cmd("edit " .. vim.fn.fnameescape(hit.document))
		local line = hit.line
		if type(line) == "number" and line > 0 then
			-- Current window (0) is the buffer we just opened.
			cursor(0, { line, 0 })
		end
		return
	end

	-- Neither branch usable — surface as an error so the picker adapter
	-- can vim.notify it rather than silently do nothing.
	error("jump.to_hit: hit has neither a resolvable `tag` nor a `document`")
end

return M
