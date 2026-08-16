--- telescope.nvim adapter.
---
--- telescope is an optional peer — this module fails loud with an
--- actionable message if it isn't loadable. The dispatcher
--- (`vimhelp.picker`) is expected to have checked availability before
--- routing here; a direct call bypassing the dispatcher shouldn't
--- produce a mysterious require error.

local jump = require("vimhelp.jump")

local M = {}

--- Shape a domain hit into telescope's entry table. Pure — no telescope
--- API touch — so tests assert the shape without needing telescope
--- loaded.
--- The `ordinal` field is what telescope's fuzzy sorter matches
--- against; combining tag + header + document lets the user narrow by
--- any of the three interchangeably.
--- @param hit table
--- @return table  { value, display, ordinal }
function M.entry_for(hit)
	local tag = hit.tag or "<no tag>"
	local header = hit.section_header or "<no header>"
	local document = hit.document or "<no doc>"
	local line = hit.line or 0
	return {
		value = hit,
		display = string.format("%-40s  %s:%d  — %s", tag, document, line, header),
		ordinal = string.format("%s %s %s", tag, header, document),
	}
end

--- Open a telescope picker with the given search result. On selection,
--- closes the prompt and jumps to the hit via `vimhelp.jump.to_hit`.
--- @param result { query: string, hits: table[] }
--- @param deps table? { telescope: table (test seam for each submodule), jump: fun(hit) }
function M.pick(result, deps)
	deps = deps or {}

	-- deps.telescope, when provided by a test, is a table shaped like the
	-- three submodules we actually use — { pickers, finders, config,
	-- actions, actions_state, sorters }. Skips the require chain and the
	-- need to have telescope installed at test time.
	local mods = deps.telescope
	if not mods then
		local ok_p, pickers = pcall(require, "telescope.pickers")
		local ok_f, finders = pcall(require, "telescope.finders")
		local ok_c, conf = pcall(require, "telescope.config")
		local ok_a, actions = pcall(require, "telescope.actions")
		local ok_s, state = pcall(require, "telescope.actions.state")
		if not (ok_p and ok_f and ok_c and ok_a and ok_s) then
			error(
				"vimhelp.pickers.telescope: telescope.nvim is not loadable — "
					.. "install nvim-telescope/telescope.nvim or set `picker = 'snacks'` / `'messages'`"
			)
		end
		mods = {
			pickers = pickers,
			finders = finders,
			sorter = conf.values.generic_sorter({}),
			actions = actions,
			state = state,
		}
	end
	local do_jump = deps.jump or jump.to_hit

	local entries = {}
	for _, h in ipairs(result.hits) do
		entries[#entries + 1] = M.entry_for(h)
	end

	mods.pickers
		.new({}, {
			prompt_title = string.format("vimhelp: %s", result.query),
			finder = mods.finders.new_table({
				results = entries,
				entry_maker = function(e)
					return e -- entries are pre-shaped
				end,
			}),
			sorter = mods.sorter,
			attach_mappings = function(prompt_bufnr, _map)
				mods.actions.select_default:replace(function()
					mods.actions.close(prompt_bufnr)
					local selection = mods.state.get_selected_entry()
					if selection and selection.value then
						do_jump(selection.value)
					end
				end)
				return true
			end,
		})
		:find()
end

return M
