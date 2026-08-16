--- Fallback picker: print rendered hits to :messages. No interactive
--- selection — this backend is what runs on bare Neovim where neither
--- snacks nor telescope is available.
---
--- The picker.pick dispatcher hands each backend a uniform
--- {result, deps} pair; `pick` in each backend is the only public
--- function. Keeps the dispatch loop trivial.

local search = require("vimhelp.search")

local M = {}

--- Render the result and print it. deps.printer is injectable so tests
--- can capture output without touching :messages.
--- @param result { query: string, hits: table[] }
--- @param deps table? { printer: fun(text: string) }
function M.pick(result, deps)
	deps = deps or {}
	local printer = deps.printer or print
	printer(search.render(result))
end

return M
