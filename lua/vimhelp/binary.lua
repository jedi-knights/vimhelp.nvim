--- Subprocess invocation of the vimhelp-index CLI.
---
--- Split from search.lua so JSON parsing stays pure (testable without
--- a real binary). The runner is a single injectable seam: production
--- uses `vim.system(...):wait()`; tests inject a fake that returns a
--- canned `{code, stdout, stderr}` triple.

local M = {}

--- Resolve the binary path from config or PATH lookup.
--- @param binary_path string? Explicit override; when nil we probe PATH.
--- @return string? path to executable, or nil when not found.
function M.resolve(binary_path)
	if type(binary_path) == "string" and #binary_path > 0 then
		if vim.fn.executable(binary_path) == 1 then
			return binary_path
		end
		return nil
	end
	if vim.fn.executable("vimhelp-index") == 1 then
		return "vimhelp-index"
	end
	return nil
end

--- Default runner: blocking `vim.system(...):wait()`. Split into a
--- module-local function so tests inject a fake instead. Blocking is
--- fine for now — tantivy queries land under 100ms — and simplifies
--- the caller's error handling. Refactor to async when a picker adds
--- interactive pressure.
local function default_runner(argv)
	local result = vim.system(argv, { text = true }):wait()
	return {
		code = result.code,
		stdout = result.stdout or "",
		stderr = result.stderr or "",
	}
end

--- Run `vimhelp-index search --index=<dir> --format=json --limit=<N> <query>`
--- and return the raw `{code, stdout, stderr}` triple.
--- @param bin string Resolved binary path (from M.resolve).
--- @param index_dir string
--- @param query string
--- @param limit integer  0 delegates to the CLI's default cap.
--- @param deps table? { runner: fun(argv): {code,stdout,stderr} }
--- @return table result
function M.search(bin, index_dir, query, limit, deps)
	assert(type(bin) == "string" and #bin > 0, "binary.search: bin required")
	assert(type(index_dir) == "string" and #index_dir > 0, "binary.search: index_dir required")
	assert(type(query) == "string" and #query > 0, "binary.search: query required")
	deps = deps or {}
	local runner = deps.runner or default_runner
	local argv = {
		bin,
		"search",
		"--index",
		index_dir,
		"--format",
		"json",
		"--limit",
		tostring(limit),
		query,
	}
	return runner(argv)
end

return M
