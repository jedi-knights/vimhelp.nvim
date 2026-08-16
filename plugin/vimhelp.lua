-- vimhelp: Neovim plugin entry point.
-- Loaded on startup; keeps this file tiny and defers real work to the
-- lua/vimhelp/ module so :source and :Lazy reload behave.

if vim.g.loaded_vimhelp then
	return
end
vim.g.loaded_vimhelp = 1

-- Augroup is declared here and reused by lua/vimhelp/init.lua.
-- clear = true is required — a stale augroup from a previous :source
-- would fire autocmds twice.
vim.api.nvim_create_augroup("vimhelp", { clear = true })

-- Command registration is intentionally in plugin/ (not deferred into
-- setup()) so users get :VimHelpSearch without any require() ceremony.
-- The lambda defers `require("vimhelp")` until first invocation, so
-- startup cost is one nvim_create_user_command call.
vim.api.nvim_create_user_command("VimHelpSearch", function(opts)
	-- opts.args is the whole tail after the command name — multi-word
	-- queries like `:VimHelpSearch floating window` arrive as a single
	-- string, not a list. Trim to reject `:VimHelpSearch    ` with
	-- only whitespace before the domain validator rejects it too.
	local query = vim.trim(opts.args)
	if query == "" then
		vim.notify("VimHelpSearch: expected a query", vim.log.levels.ERROR)
		return
	end
	local ok, err = pcall(require("vimhelp").search, query)
	if not ok then
		vim.notify(tostring(err), vim.log.levels.ERROR)
	end
end, {
	nargs = "+",
	desc = "Full-text search over :help via vimhelp-index",
})
