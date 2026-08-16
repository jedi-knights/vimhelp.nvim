--- Jump to a selected search hit.
---
--- Split from picker adapters so every backend (snacks, telescope, the
--- messages fallback via a follow-up user command) invokes the same
--- landing behaviour. Pure via injectable `cmd` + `cursor` seams so
--- tests never touch the real editor.

local M = {}

--- Land the cursor on the requested hit.
---
--- Preference order:
---   1. `hit.tag` non-empty → `:help <tag>` (opens the help buffer at
---      the tag exactly the way a user typed `:h <tag>` would).
---   2. Otherwise → `:edit <document>` and set cursor to `hit.line`.
---      This handles the tag-less case (e.g. matches inside body text
---      of a docs file without a nearby tag).
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
		cmd("help " .. vim.fn.fnameescape(hit.tag))
		return
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
	error("jump.to_hit: hit has neither `tag` nor `document`")
end

return M
