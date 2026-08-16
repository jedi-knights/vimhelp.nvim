--- Default configuration and merge logic for vimhelp.

local M = {}

M.defaults = {
	enabled = true,
	-- add your defaults here
}

--- Deep-merge user opts over defaults. User values win on conflict.
--- @param opts table
--- @return table
function M.merge(opts)
	return vim.tbl_deep_extend("force", {}, M.defaults, opts)
end

return M
