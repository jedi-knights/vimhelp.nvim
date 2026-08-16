--- Runtime environment detection for vimhelp.
--- Return false from should_load() to skip setup on unsupported hosts
--- (missing peers, wrong filetype, older Neovim, feature-flag off).

local M = {}

--- @return boolean should_load true when the plugin can run here
function M.should_load()
	return true
end

return M
