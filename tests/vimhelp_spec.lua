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
end)
