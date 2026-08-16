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
