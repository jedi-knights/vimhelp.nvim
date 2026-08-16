describe("vimhelp", function()
	local mod

	before_each(function()
		package.loaded["vimhelp"] = nil
		package.loaded["vimhelp.config"] = nil
		package.loaded["vimhelp.binary"] = nil
		package.loaded["vimhelp.search"] = nil
		mod = require("vimhelp")
	end)

	it("exposes a setup function", function()
		assert.is_function(mod.setup)
	end)

	it("merges opts over defaults", function()
		mod.setup({ limit = 5 })
		assert.equals(5, mod.config.limit)
	end)

	it("accepts injected dependencies", function()
		local fake = { runner = function() end }
		mod.setup({}, { runner = fake.runner })
		-- assert.equals, not assert.are.equal — neospec's leaner
		-- luassert doesn't expose plenary.busted's `are` alias table.
		assert.equals(fake.runner, mod.deps.runner)
	end)

	describe("search", function()
		it("rejects an empty query at the boundary", function()
			assert.has_error(function()
				mod.search("")
			end)
		end)

		it("errors with an actionable message when binary is unresolved", function()
			-- Point binary_path at a nonexistent file; resolve() returns
			-- nil; search() bails with a fix hint.
			mod.setup({ binary_path = "/definitely/not/a/binary" })
			local ok, err = pcall(mod.search, "any query")
			assert.is_false(ok)
			assert.is_truthy(tostring(err):match("vimhelp%-index binary not found"))
		end)
	end)

	describe("hover", function()
		--- Capture notify calls without touching :messages, and shape a
		--- deps table that keeps hover self-contained (no editor state
		--- and no real subprocess).
		local function capture_notifies()
			local calls = {}
			return function(msg, level)
				calls[#calls + 1] = { msg = msg, level = level }
			end, calls
		end

		it("notifies + returns nil when the word under cursor is empty", function()
			local notify, calls = capture_notifies()
			mod.setup({ binary_path = "/absolutely-nope" }) -- won't be reached
			local r = mod.hover({
				word_getter = function()
					return ""
				end,
				notify = notify,
			})
			assert.is_nil(r)
			assert.equals(1, #calls)
			assert.is_truthy(calls[1].msg:match("no word under cursor"))
			-- Level for informational (not error) — no word is user state,
			-- not a plugin failure.
			assert.equals(vim.log.levels.INFO, calls[1].level)
		end)

		it("notifies at ERROR level when binary is unresolved (no throw)", function()
			local notify, calls = capture_notifies()
			mod.setup({ binary_path = "/definitely/not/a/binary" })
			local r = mod.hover({
				word_getter = function()
					return "some-word"
				end,
				notify = notify,
			})
			assert.is_nil(r)
			assert.equals(1, #calls)
			assert.is_truthy(calls[1].msg:match("vimhelp%-index binary not found"))
			assert.equals(vim.log.levels.ERROR, calls[1].level)
		end)

		it("jumps to the top hit via the injected jump when hits are returned", function()
			-- Fake a resolvable binary by pointing binary_path at a real
			-- executable on the test host — the runner is stubbed so the
			-- binary is never actually invoked; only resolve() has to
			-- pass the executable check.
			local nvim_bin = vim.v.progpath -- always executable in a running Neovim
			-- index_dir must also exist so the isdirectory check passes.
			local tmp = vim.fn.tempname()
			vim.fn.mkdir(tmp, "p")

			mod.setup({ binary_path = nvim_bin, index_dir = tmp })

			local captured_argv
			local runner = function(argv)
				captured_argv = argv
				return {
					code = 0,
					stdout = vim.json.encode({
						query = "some-word",
						hits = {
							{
								document = "doc/a.txt",
								tag = "top-hit",
								section_header = "S",
								line = 42,
								score = 3.14,
								snippet = "body",
							},
							{
								document = "doc/b.txt",
								tag = "runner-up",
								section_header = "S2",
								line = 88,
								score = 1.23,
								snippet = "body2",
							},
						},
					}),
					stderr = "",
				}
			end
			local jumped
			local notify = function() end

			local r = mod.hover({
				word_getter = function()
					return "some-word"
				end,
				notify = notify,
				runner = runner,
				jump = function(hit)
					jumped = hit
				end,
			})

			-- Top hit wins.
			assert.is_not_nil(jumped)
			assert.equals("top-hit", jumped.tag)
			-- Fixed limit=1 for hover — the CLI --limit arg should be "1",
			-- independent of the config.limit (default 20).
			assert.equals("1", captured_argv[8])
			-- Returns the raw parsed result so downstream callers (e.g. a
			-- future "show alternatives" wrapper) can inspect it.
			assert.is_not_nil(r)
			assert.equals(2, #r.hits)
		end)

		it("notifies + returns nil when the search returns zero hits", function()
			local nvim_bin = vim.v.progpath
			local tmp = vim.fn.tempname()
			vim.fn.mkdir(tmp, "p")
			mod.setup({ binary_path = nvim_bin, index_dir = tmp })

			local notify, calls = capture_notifies()
			local jumped
			local r = mod.hover({
				word_getter = function()
					return "no-such-word"
				end,
				notify = notify,
				runner = function()
					return {
						code = 0,
						stdout = vim.json.encode({ query = "no-such-word", hits = {} }),
						stderr = "",
					}
				end,
				jump = function(hit)
					jumped = hit
				end,
			})
			assert.is_nil(r)
			assert.is_nil(jumped)
			assert.equals(1, #calls)
			assert.is_truthy(calls[1].msg:match("no hits"))
		end)

		it("notifies at ERROR + returns nil when the subprocess exits non-zero", function()
			local nvim_bin = vim.v.progpath
			local tmp = vim.fn.tempname()
			vim.fn.mkdir(tmp, "p")
			mod.setup({ binary_path = nvim_bin, index_dir = tmp })

			local notify, calls = capture_notifies()
			local jumped
			local r = mod.hover({
				word_getter = function()
					return "any"
				end,
				notify = notify,
				runner = function()
					return { code = 3, stdout = "", stderr = "boom" }
				end,
				jump = function(hit)
					jumped = hit
				end,
			})
			assert.is_nil(r)
			assert.is_nil(jumped)
			assert.equals(1, #calls)
			assert.equals(vim.log.levels.ERROR, calls[1].level)
			assert.is_truthy(calls[1].msg:match("code 3"))
			assert.is_truthy(calls[1].msg:match("boom"))
		end)
	end)

	describe("build", function()
		local function capture_notifies()
			local calls = {}
			return function(msg, level)
				calls[#calls + 1] = { msg = msg, level = level }
			end, calls
		end

		it("notifies + returns false when the binary is unresolved", function()
			local notify, calls = capture_notifies()
			mod.setup({ binary_path = "/definitely/not/a/binary" })
			local ok = mod.build({}, { notify = notify })
			assert.is_false(ok)
			assert.equals(vim.log.levels.ERROR, calls[1].level)
			assert.is_truthy(calls[1].msg:match("vimhelp%-index binary not found"))
		end)

		it("notifies progress + success + returns true on happy path", function()
			mod.setup({
				binary_path = vim.v.progpath, -- executable check passes
				auto_index_docs = "/some/glob/*.txt",
			})
			local captured_argv
			local notify, calls = capture_notifies()
			local ok = mod.build({}, {
				notify = notify,
				runner = function(argv)
					captured_argv = argv
					return {
						code = 0,
						stdout = "Indexed 12 section(s) from 3 file(s) → /tmp/idx",
						stderr = "",
					}
				end,
			})
			assert.is_true(ok)
			-- Progress notify first, CLI-summary notify second.
			assert.equals(2, #calls)
			assert.is_truthy(calls[1].msg:match("building index"))
			assert.equals(vim.log.levels.INFO, calls[1].level)
			assert.is_truthy(calls[2].msg:match("Indexed 12 section"))
			-- argv shape: sees the configured docs glob.
			assert.equals("/some/glob/*.txt", captured_argv[4])
		end)

		it("appends --incremental when opts.incremental=true", function()
			mod.setup({ binary_path = vim.v.progpath })
			local captured_argv
			mod.build({ incremental = true }, {
				notify = function() end,
				runner = function(argv)
					captured_argv = argv
					return { code = 0, stdout = "ok", stderr = "" }
				end,
			})
			assert.equals("--incremental", captured_argv[7])
		end)

		it("notifies ERROR + returns false on non-zero CLI exit", function()
			mod.setup({ binary_path = vim.v.progpath })
			local notify, calls = capture_notifies()
			local ok = mod.build({}, {
				notify = notify,
				runner = function()
					return { code = 2, stdout = "", stderr = "no files matched" }
				end,
			})
			assert.is_false(ok)
			-- Progress notify first, error notify second.
			assert.equals(2, #calls)
			assert.equals(vim.log.levels.ERROR, calls[2].level)
			assert.is_truthy(calls[2].msg:match("exit 2"))
			assert.is_truthy(calls[2].msg:match("no files matched"))
		end)

		it("expands `auto_index_docs` list into repeated --docs argv entries", function()
			mod.setup({
				binary_path = vim.v.progpath,
				auto_index_docs = { "/a/*.txt", "/b/*.txt", "/c/*.txt" },
			})
			local captured_argv
			mod.build({}, {
				notify = function() end,
				runner = function(argv)
					captured_argv = argv
					return { code = 0, stdout = "ok", stderr = "" }
				end,
			})
			-- Bin, "build", then each --docs pair, then --out /tmp/...
			assert.equals("--docs", captured_argv[3])
			assert.equals("/a/*.txt", captured_argv[4])
			assert.equals("--docs", captured_argv[5])
			assert.equals("/b/*.txt", captured_argv[6])
			assert.equals("--docs", captured_argv[7])
			assert.equals("/c/*.txt", captured_argv[8])
			assert.equals("--out", captured_argv[9])
		end)

		it("notifies + returns false when auto_index_docs is a bad type", function()
			mod.setup({
				binary_path = vim.v.progpath,
				---@diagnostic disable-next-line: assign-type-mismatch
				auto_index_docs = 42, -- users occasionally mis-type; must not traceback
			})
			local notify, calls = capture_notifies()
			local ok = mod.build({}, {
				notify = notify,
				runner = function()
					error("runner should not be called when normalization fails")
				end,
			})
			assert.is_false(ok)
			-- The type error surfaces as a notify, not a Lua traceback.
			assert.is_truthy(calls[#calls].msg:match("auto_index_docs must be a string or a table"))
		end)

		it("notifies + returns false when auto_index_docs is an empty table", function()
			mod.setup({
				binary_path = vim.v.progpath,
				auto_index_docs = {},
			})
			local notify, calls = capture_notifies()
			local ok = mod.build({}, {
				notify = notify,
				runner = function()
					error("runner should not be called")
				end,
			})
			assert.is_false(ok)
			assert.is_truthy(calls[#calls].msg:match("must not be empty"))
		end)
	end)

	describe("build_async", function()
		local function capture_notifies()
			local calls = {}
			return function(msg, level)
				calls[#calls + 1] = { msg = msg, level = level }
			end, calls
		end

		-- Fake async runner: matches the (argv, on_done) shape and calls
		-- the callback synchronously with the canned result. Tests are
		-- single-threaded so this is deterministic without vim.schedule.
		local function fake_async_runner(canned)
			return function(_argv, on_done)
				on_done(canned)
			end
		end

		it("notifies + on_done(false) when the binary is unresolved", function()
			mod.setup({ binary_path = "/definitely/not/a/binary" })
			local notify, calls = capture_notifies()
			local received
			mod.build_async({}, {
				notify = notify,
				async_runner = function()
					error("async_runner should not be reached when bin missing")
				end,
			}, function(ok)
				received = ok
			end)
			assert.is_false(received)
			assert.equals(vim.log.levels.ERROR, calls[1].level)
			assert.is_truthy(calls[1].msg:match("vimhelp%-index binary not found"))
		end)

		it("notifies progress + success and calls on_done(true) on happy path", function()
			mod.setup({
				binary_path = vim.v.progpath,
				auto_index_docs = "/some/glob/*.txt",
			})
			local captured_argv
			local notify, calls = capture_notifies()
			local received
			mod.build_async({}, {
				notify = notify,
				async_runner = function(argv, on_done)
					captured_argv = argv
					on_done({
						code = 0,
						stdout = "Indexed 4 section(s) from 1 file(s) → /tmp/idx",
						stderr = "",
					})
				end,
			}, function(ok)
				received = ok
			end)
			assert.is_true(received)
			-- Progress notify first, CLI-summary notify second.
			assert.equals(2, #calls)
			assert.is_truthy(calls[1].msg:match("building index"))
			assert.is_truthy(calls[2].msg:match("Indexed 4 section"))
			assert.equals("/some/glob/*.txt", captured_argv[4])
		end)

		it("appends --incremental when opts.incremental=true", function()
			mod.setup({ binary_path = vim.v.progpath })
			local captured_argv
			mod.build_async({ incremental = true }, {
				notify = function() end,
				async_runner = function(argv, on_done)
					captured_argv = argv
					on_done({ code = 0, stdout = "ok", stderr = "" })
				end,
			})
			assert.equals("--incremental", captured_argv[7])
		end)

		it("notifies ERROR + on_done(false) on non-zero CLI exit", function()
			mod.setup({ binary_path = vim.v.progpath })
			local notify, calls = capture_notifies()
			local received
			mod.build_async({}, {
				notify = notify,
				async_runner = fake_async_runner({ code = 2, stdout = "", stderr = "no files matched" }),
			}, function(ok)
				received = ok
			end)
			assert.is_false(received)
			assert.equals(2, #calls)
			assert.equals(vim.log.levels.ERROR, calls[2].level)
			assert.is_truthy(calls[2].msg:match("exit 2"))
			assert.is_truthy(calls[2].msg:match("no files matched"))
		end)

		it("notifies + on_done(false) when auto_index_docs is a bad type", function()
			mod.setup({
				binary_path = vim.v.progpath,
				---@diagnostic disable-next-line: assign-type-mismatch
				auto_index_docs = 42,
			})
			local notify, calls = capture_notifies()
			local received
			mod.build_async({}, {
				notify = notify,
				async_runner = function()
					error("async_runner should not be called when normalization fails")
				end,
			}, function(ok)
				received = ok
			end)
			assert.is_false(received)
			assert.is_truthy(calls[#calls].msg:match("auto_index_docs must be a string or a table"))
		end)

		it("is safe to call without an on_done callback (fire-and-forget)", function()
			-- The :VimHelpBuild command doesn't care about the result — the
			-- notify lines are the surface. Missing callback must not throw
			-- (neospec's luassert lacks `assert.has_no.errors`; a raw call
			-- surfaces any throw as a test failure just as clearly).
			mod.setup({ binary_path = vim.v.progpath })
			mod.build_async({}, {
				notify = function() end,
				async_runner = fake_async_runner({ code = 0, stdout = "ok", stderr = "" }),
			})
		end)
	end)

	describe("ensure_index", function()
		it("returns nil when the index directory already exists", function()
			local tmp = vim.fn.tempname()
			vim.fn.mkdir(tmp, "p")
			mod.setup({ index_dir = tmp })
			assert.is_nil(mod.ensure_index())
		end)

		it("returns an actionable error message when auto_index is off + index missing", function()
			mod.setup({ index_dir = "/definitely/not/a/dir", auto_index = false })
			local err = mod.ensure_index()
			assert.is_string(err)
			-- Names the fix paths: :VimHelpBuild + auto_index config key.
			assert.is_truthy(err:match(":VimHelpBuild"))
			assert.is_truthy(err:match("auto_index"))
		end)

		it("delegates to M.build when auto_index=true and returns nil on success", function()
			-- index_dir missing → we should hit M.build. Point the runner
			-- at success and don't actually create the dir; ensure_index
			-- trusts M.build's return value.
			mod.setup({
				binary_path = vim.v.progpath,
				index_dir = "/tmp/definitely-missing-vh-" .. tostring(math.random()),
				auto_index = true,
			})
			local build_called = false
			assert.is_nil(mod.ensure_index({
				notify = function() end,
				runner = function()
					build_called = true
					return { code = 0, stdout = "Indexed", stderr = "" }
				end,
			}))
			assert.is_true(build_called)
		end)

		it("returns a short error message when the auto-build fails", function()
			mod.setup({
				binary_path = vim.v.progpath,
				index_dir = "/tmp/definitely-missing-vh-" .. tostring(math.random()),
				auto_index = true,
			})
			local err = mod.ensure_index({
				notify = function() end,
				runner = function()
					return { code = 3, stdout = "", stderr = "boom" }
				end,
			})
			assert.is_string(err)
			assert.is_truthy(err:match("auto%-build failed"))
		end)
	end)
end)
