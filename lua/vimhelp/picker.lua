--- Picker dispatcher.
---
--- `pick(result, opts)` routes a search result to whichever backend
--- opts.picker resolves to. `choose(preferred)` is exported separately
--- so `:checkhealth` can report which backend the user is actually
--- getting without opening a picker.

local M = {}

--- Names of supported backends. Extending this list requires adding a
--- corresponding module under `lua/vimhelp/pickers/`.
M.BACKENDS = { "snacks", "telescope", "messages" }

--- Cheap check whether a module can be loaded, without side-effecting
--- the require cache with a partial or failing load. Uses
--- package.loaded first (avoids repeated searcher work) and then
--- pcall(require) as the actual availability test.
local function has_module(name, deps)
	deps = deps or {}
	if deps.has_module then
		return deps.has_module(name)
	end
	if package.loaded[name] ~= nil then
		return true
	end
	local ok = pcall(require, name)
	return ok
end

--- Choose the concrete backend given the user's preference. Falls back
--- to "messages" whenever the preferred backend isn't available so
--- `:VimHelpSearch` never errors just because a peer isn't loaded.
--- @param preferred string?  "auto" (default) | "snacks" | "telescope" | "messages"
--- @param deps table?  { has_module: fun(name)->boolean } — test seam
--- @return string  one of BACKENDS
function M.choose(preferred, deps)
	preferred = preferred or "auto"
	if preferred == "messages" then
		return "messages"
	end
	if preferred == "snacks" then
		return has_module("snacks", deps) and "snacks" or "messages"
	end
	if preferred == "telescope" then
		return has_module("telescope", deps) and "telescope" or "messages"
	end
	-- auto: snacks first (folke's picker is faster and prettier out of
	-- the box), then telescope, then plain messages.
	if has_module("snacks", deps) then
		return "snacks"
	end
	if has_module("telescope", deps) then
		return "telescope"
	end
	return "messages"
end

--- Route the search result to a picker backend and open it.
--- @param result { query: string, hits: table[] }
--- @param opts table?  { picker: string, ... }
--- @param deps table?  { has_module, pickers: {[name]: table} } — test seam
function M.pick(result, opts, deps)
	opts = opts or {}
	deps = deps or {}
	local backend = M.choose(opts.picker, deps)
	local impl
	if deps.pickers and deps.pickers[backend] then
		impl = deps.pickers[backend]
	else
		impl = require("vimhelp.pickers." .. backend)
	end
	impl.pick(result, opts)
end

return M
