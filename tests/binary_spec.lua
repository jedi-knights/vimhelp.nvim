describe("vimhelp.binary", function()
	local binary

	before_each(function()
		package.loaded["vimhelp.binary"] = nil
		binary = require("vimhelp.binary")
	end)

	describe("resolve", function()
		it("returns nil when no override and PATH lookup fails", function()
			-- vimhelp-index isn't installed in the test env; PATH probe fails.
			-- (If a future CI runner has it installed, this test would need
			-- to inject a fake `executable` — deferred until it bites.)
			assert.is_nil(binary.resolve(nil))
		end)

		it("returns nil when the override path is not executable", function()
			assert.is_nil(binary.resolve("/absolutely/not/a/real/binary"))
		end)

		-- Positive cases (override IS executable, PATH DOES resolve) are
		-- covered by the health-check integration in :checkhealth and by
		-- manual smoke — testing them here would require either a fake
		-- executable on disk or a monkey-patched vim.fn.executable, both
		-- of which add more surface than they earn at this layer.
	end)

	describe("search", function()
		-- Build a fake runner that captures argv and returns a canned
		-- {code, stdout, stderr} triple so the shape of the argv we send
		-- to the CLI is asserted without spawning anything.
		local function capturing_runner(canned)
			local captured
			local runner = function(argv)
				captured = argv
				return canned or { code = 0, stdout = "{}", stderr = "" }
			end
			return runner, function()
				return captured
			end
		end

		it("assembles the expected argv", function()
			local runner, get_argv = capturing_runner()
			binary.search("vimhelp-index", "/tmp/idx", "floating window", 20, { runner = runner })
			assert.same({
				"vimhelp-index",
				"search",
				"--index",
				"/tmp/idx",
				"--format",
				"json",
				"--limit",
				"20",
				"floating window",
			}, get_argv())
		end)

		it("passes limit=0 through as the CLI-default sentinel", function()
			local runner, get_argv = capturing_runner()
			binary.search("vimhelp-index", "/tmp/idx", "q", 0, { runner = runner })
			assert.equals("0", get_argv()[8])
		end)

		it("returns the runner's result verbatim", function()
			local runner = function()
				return { code = 3, stdout = "S", stderr = "E" }
			end
			local r = binary.search("bin", "/tmp", "q", 20, { runner = runner })
			assert.equals(3, r.code)
			assert.equals("S", r.stdout)
			assert.equals("E", r.stderr)
		end)

		it("rejects empty bin / index_dir / query at the boundary", function()
			local runner = function()
				return { code = 0, stdout = "{}", stderr = "" }
			end
			assert.has_error(function()
				binary.search("", "/tmp", "q", 20, { runner = runner })
			end)
			assert.has_error(function()
				binary.search("bin", "", "q", 20, { runner = runner })
			end)
			assert.has_error(function()
				binary.search("bin", "/tmp", "", 20, { runner = runner })
			end)
		end)
	end)

	describe("build", function()
		local function capturing_runner(canned)
			local captured
			local runner = function(argv)
				captured = argv
				return canned or { code = 0, stdout = "Indexed 3 sections", stderr = "" }
			end
			return runner, function()
				return captured
			end
		end

		it("assembles the expected argv for one glob without --incremental", function()
			local runner, get_argv = capturing_runner()
			binary.build("vimhelp-index", { "/path/*.txt" }, "/tmp/idx", {}, { runner = runner })
			assert.same({
				"vimhelp-index",
				"build",
				"--docs",
				"/path/*.txt",
				"--out",
				"/tmp/idx",
			}, get_argv())
		end)

		it("emits one --docs per entry when passed multiple globs", function()
			local runner, get_argv = capturing_runner()
			binary.build("vimhelp-index", { "/a/*.txt", "/b/*.txt", "/c/*.txt" }, "/tmp/idx", {}, { runner = runner })
			assert.same({
				"vimhelp-index",
				"build",
				"--docs",
				"/a/*.txt",
				"--docs",
				"/b/*.txt",
				"--docs",
				"/c/*.txt",
				"--out",
				"/tmp/idx",
			}, get_argv())
		end)

		it("appends --incremental after --out when opts.incremental is true", function()
			local runner, get_argv = capturing_runner()
			binary.build("vimhelp-index", { "/p/*.txt" }, "/tmp/idx", { incremental = true }, {
				runner = runner,
			})
			-- Slot 7 = "--incremental" (bin, build, --docs, /p/*.txt, --out, /tmp/idx, --incremental).
			assert.equals("--incremental", get_argv()[7])
		end)

		it("returns the runner's result verbatim", function()
			local runner = function()
				return { code = 5, stdout = "OUT", stderr = "ERR" }
			end
			local r = binary.build("bin", { "g" }, "/tmp", {}, { runner = runner })
			assert.equals(5, r.code)
			assert.equals("OUT", r.stdout)
			assert.equals("ERR", r.stderr)
		end)

		it("rejects empty bin / docs_globs / out_dir at the boundary", function()
			local runner = function()
				return { code = 0, stdout = "", stderr = "" }
			end
			assert.has_error(function()
				binary.build("", { "g" }, "/tmp", {}, { runner = runner })
			end)
			-- Empty list.
			assert.has_error(function()
				binary.build("bin", {}, "/tmp", {}, { runner = runner })
			end)
			-- Non-list value.
			assert.has_error(function()
				---@diagnostic disable-next-line: param-type-mismatch
				binary.build("bin", "single_string_not_allowed_here", "/tmp", {}, { runner = runner })
			end)
			-- Entry that's not a non-empty string.
			assert.has_error(function()
				binary.build("bin", { "" }, "/tmp", {}, { runner = runner })
			end)
			assert.has_error(function()
				binary.build("bin", { "g" }, "", {}, { runner = runner })
			end)
		end)
	end)

	describe("build_async", function()
		-- Fake async runner: captures argv, invokes on_done synchronously
		-- with a canned result. Tests already run in the main loop so
		-- there's no vim.schedule() concern here — the real default
		-- runner is what needs it (see binary.lua).
		local function capturing_async_runner(canned)
			local captured
			local runner = function(argv, on_done)
				captured = argv
				on_done(canned or { code = 0, stdout = "Indexed 3", stderr = "" })
			end
			return runner, function()
				return captured
			end
		end

		it("assembles the same argv shape as build()", function()
			local runner, get_argv = capturing_async_runner()
			binary.build_async("vimhelp-index", { "/a/*.txt", "/b/*.txt" }, "/tmp/idx", { incremental = true }, {
				async_runner = runner,
			}, function() end)
			assert.same({
				"vimhelp-index",
				"build",
				"--docs",
				"/a/*.txt",
				"--docs",
				"/b/*.txt",
				"--out",
				"/tmp/idx",
				"--incremental",
			}, get_argv())
		end)

		it("delivers the runner's result to on_done verbatim", function()
			local received
			local runner = function(_argv, on_done)
				on_done({ code = 7, stdout = "OUT", stderr = "ERR" })
			end
			binary.build_async("bin", { "g" }, "/tmp", {}, { async_runner = runner }, function(result)
				received = result
			end)
			assert.equals(7, received.code)
			assert.equals("OUT", received.stdout)
			assert.equals("ERR", received.stderr)
		end)

		it("rejects a missing on_done callback at the boundary", function()
			assert.has_error(function()
				---@diagnostic disable-next-line: param-type-mismatch
				binary.build_async("bin", { "g" }, "/tmp", {}, {}, nil)
			end)
		end)

		it("shares the same boundary rejections as build()", function()
			-- The argv-assembly path is shared, so all the empty-input
			-- rejections propagate. One spot-check per bad arg is enough;
			-- the sync path exhaustively covers the matrix.
			local runner = function(_argv, on_done)
				on_done({ code = 0, stdout = "", stderr = "" })
			end
			local noop = function() end
			assert.has_error(function()
				binary.build_async("", { "g" }, "/tmp", {}, { async_runner = runner }, noop)
			end)
			assert.has_error(function()
				binary.build_async("bin", {}, "/tmp", {}, { async_runner = runner }, noop)
			end)
			assert.has_error(function()
				binary.build_async("bin", { "g" }, "", {}, { async_runner = runner }, noop)
			end)
		end)
	end)
end)
