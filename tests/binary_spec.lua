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

		it("assembles the expected argv without --incremental by default", function()
			local runner, get_argv = capturing_runner()
			binary.build("vimhelp-index", "/path/*.txt", "/tmp/idx", {}, { runner = runner })
			assert.same({
				"vimhelp-index",
				"build",
				"--docs",
				"/path/*.txt",
				"--out",
				"/tmp/idx",
			}, get_argv())
		end)

		it("appends --incremental when opts.incremental is true", function()
			local runner, get_argv = capturing_runner()
			binary.build("vimhelp-index", "/p/*.txt", "/tmp/idx", { incremental = true }, {
				runner = runner,
			})
			assert.equals("--incremental", get_argv()[7])
		end)

		it("returns the runner's result verbatim", function()
			local runner = function()
				return { code = 5, stdout = "OUT", stderr = "ERR" }
			end
			local r = binary.build("bin", "g", "/tmp", {}, { runner = runner })
			assert.equals(5, r.code)
			assert.equals("OUT", r.stdout)
			assert.equals("ERR", r.stderr)
		end)

		it("rejects empty bin / docs / out_dir at the boundary", function()
			local runner = function()
				return { code = 0, stdout = "", stderr = "" }
			end
			assert.has_error(function()
				binary.build("", "g", "/tmp", {}, { runner = runner })
			end)
			assert.has_error(function()
				binary.build("bin", "", "/tmp", {}, { runner = runner })
			end)
			assert.has_error(function()
				binary.build("bin", "g", "", {}, { runner = runner })
			end)
		end)
	end)
end)
