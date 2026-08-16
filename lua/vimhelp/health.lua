--- :checkhealth vimhelp entry point.

local M = {}

function M.check()
	vim.health.start("vimhelp")

	local detector = require("vimhelp.detector")
	if detector.should_load() then
		vim.health.ok("environment supports vimhelp")
	else
		vim.health.warn("vimhelp would not load in this environment (detector.should_load returned false)")
	end
end

return M
