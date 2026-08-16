--- snacks.picker adapter.
---
--- snacks (folke/snacks.nvim) is an optional peer — this module fails
--- loud with an actionable message if it isn't loadable. The
--- dispatcher (`vimhelp.picker`) is expected to have checked
--- availability before routing here; a direct call bypassing the
--- dispatcher shouldn't produce a mysterious require error.

local jump = require("vimhelp.jump")

local M = {}

--- Shape a domain hit into the picker's item table. Pure — no snacks
--- API touch — so tests assert the shape without needing snacks loaded.
--- Also exported so other snacks-adjacent tooling (a future :VimHelpPick
--- inside another workflow) can reuse the same item text.
--- @param hit table
--- @return table  { text: string, hit: table }
function M.item_for(hit)
	local tag = hit.tag or "<no tag>"
	local header = hit.section_header or "<no header>"
	local text = string.format("%-40s  %s:%d  — %s", tag, hit.document or "<no doc>", hit.line or 0, header)
	return { text = text, hit = hit }
end

--- Open the snacks picker with the given search result. On confirm,
--- jumps to the selected hit via `vimhelp.jump.to_hit`.
--- @param result { query: string, hits: table[] }
--- @param deps table? { snacks: table (test seam), jump: fun(hit) }
function M.pick(result, deps)
	deps = deps or {}
	local snacks = deps.snacks
	if not snacks then
		local ok, mod = pcall(require, "snacks")
		if not ok then
			error(
				"vimhelp.pickers.snacks: snacks.nvim is not loadable — "
					.. "install folke/snacks.nvim or set `picker = 'telescope'` / `'messages'`"
			)
		end
		snacks = mod
	end
	local do_jump = deps.jump or jump.to_hit

	local items = {}
	for _, h in ipairs(result.hits) do
		items[#items + 1] = M.item_for(h)
	end

	snacks.picker.pick({
		title = string.format("vimhelp: %s", result.query),
		items = items,
		format = function(item)
			return { { item.text, "SnacksPickerLabel" } }
		end,
		confirm = function(picker, item)
			picker:close()
			if item and item.hit then
				do_jump(item.hit)
			end
		end,
	})
end

return M
