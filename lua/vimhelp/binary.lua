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

--- Default sync runner: blocking `vim.system(...):wait()`. Split into
--- a module-local function so tests inject a fake instead. Blocking is
--- fine for search — tantivy queries land under 100ms — and simplifies
--- the caller's error handling. Builds go through the async path
--- (default_async_runner) so `:VimHelpBuild` doesn't lock up the
--- editor while tantivy chews through the docs corpus.
local function default_runner(argv)
	local result = vim.system(argv, { text = true }):wait()
	return {
		code = result.code,
		stdout = result.stdout or "",
		stderr = result.stderr or "",
	}
end

--- Default async runner: `vim.system(argv, {text=true}, on_exit)` with
--- no `:wait()`. The on_exit callback runs in a Neovim "fast" event
--- context where `vim.api` (and therefore `vim.notify`) is forbidden,
--- so we wrap the caller's `on_done` in `vim.schedule` — every callback
--- fires on the main loop and is free to touch the API.
local function default_async_runner(argv, on_done)
	vim.system(argv, { text = true }, function(result)
		vim.schedule(function()
			on_done({
				code = result.code,
				stdout = result.stdout or "",
				stderr = result.stderr or "",
			})
		end)
	end)
end

--- Build the argv vector shared by sync + async build. Assertions live
--- here so both entry points fail-fast on bad input at exactly the same
--- boundary (empty bin, non-list globs, empty entries, empty out_dir).
local function build_argv(bin, docs_globs, out_dir, opts)
	assert(type(bin) == "string" and #bin > 0, "binary.build: bin required")
	assert(
		type(docs_globs) == "table" and #docs_globs > 0,
		"binary.build: docs_globs must be a non-empty list of glob strings"
	)
	assert(type(out_dir) == "string" and #out_dir > 0, "binary.build: out_dir required")
	local argv = { bin, "build" }
	for _, glob in ipairs(docs_globs) do
		assert(type(glob) == "string" and #glob > 0, "binary.build: each docs_globs entry must be a non-empty string")
		table.insert(argv, "--docs")
		table.insert(argv, glob)
	end
	table.insert(argv, "--out")
	table.insert(argv, out_dir)
	if opts and opts.incremental then
		table.insert(argv, "--incremental")
	end
	return argv
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

--- Run `vimhelp-index build --docs=<glob> [--docs=<glob>...] --out=<dir> [--incremental]`.
---
--- `docs_globs` is a non-empty list of glob strings — every entry becomes
--- one `--docs` flag. The CLI unions the resolved paths (see
--- vimhelp-index PR #11). Callers with a single glob wrap it in a
--- one-element table; the facade (`vimhelp.M.build`) does that
--- normalization on the user's `auto_index_docs` config value.
---
--- @param bin string Resolved binary path.
--- @param docs_globs string[] One or more glob strings; each becomes a --docs flag.
--- @param out_dir string Where the index gets written.
--- @param opts table? { incremental: boolean }
--- @param deps table? { runner: fun(argv): {code,stdout,stderr} }
--- @return table result  { code, stdout, stderr }
function M.build(bin, docs_globs, out_dir, opts, deps)
	deps = deps or {}
	local runner = deps.runner or default_runner
	return runner(build_argv(bin, docs_globs, out_dir, opts))
end

--- Async twin of M.build — same argv, non-blocking. `on_done(result)`
--- fires on the main loop with the same `{code, stdout, stderr}` shape
--- the sync runner returns.
---
--- The plugin's :VimHelpBuild command uses this so tantivy indexing
--- doesn't lock up the editor. `deps.async_runner` is a separate seam
--- from `deps.runner` because the signatures differ: sync returns a
--- result, async takes a callback. Same seam would collapse the type.
---
--- Note on safety while a build is running: search stays functional
--- because tantivy commits atomically (see vimhelp-index adapters/
--- tantivy.rs) — a concurrent search sees the old snapshot xor the
--- new one, never a torn state.
---
--- @param bin string
--- @param docs_globs string[]
--- @param out_dir string
--- @param opts table? { incremental: boolean }
--- @param deps table? { async_runner: fun(argv, on_done) }
--- @param on_done fun(result: {code:integer, stdout:string, stderr:string})
function M.build_async(bin, docs_globs, out_dir, opts, deps, on_done)
	assert(type(on_done) == "function", "binary.build_async: on_done callback required")
	deps = deps or {}
	local async_runner = deps.async_runner or default_async_runner
	async_runner(build_argv(bin, docs_globs, out_dir, opts), on_done)
end

return M
