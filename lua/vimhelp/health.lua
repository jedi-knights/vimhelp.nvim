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

	-- Binary discovery — the whole plugin is a shim over the CLI, so
	-- a missing binary is the most common "why doesn't :VimHelpSearch
	-- work?" cause. Surface it in checkhealth so users get the answer
	-- without having to invoke the command first.
	local binary = require("vimhelp.binary")
	local mod = require("vimhelp")
	local bin = binary.resolve(mod.config and mod.config.binary_path)
	if bin then
		vim.health.ok(string.format("vimhelp-index found: %s", bin))
	else
		vim.health.error(
			"vimhelp-index not found on PATH. Install from "
				.. "https://github.com/jedi-knights/vimhelp-index/releases "
				.. "or set require('vimhelp').setup({ binary_path = '<path>' })"
		)
	end

	-- Index presence — a missing index turns every :VimHelpSearch call
	-- into an error. Point at the build command in the report so users
	-- can fix without leaving Neovim.
	local index_dir = mod.config and mod.config.index_dir or ""
	if vim.fn.isdirectory(index_dir) == 1 then
		vim.health.ok(string.format("index directory present: %s", index_dir))
	else
		vim.health.warn(
			string.format(
				"index directory missing: %s. Build it with: vimhelp-index build --docs='<glob>' --out=%s",
				index_dir,
				index_dir
			)
		)
	end
end

return M
