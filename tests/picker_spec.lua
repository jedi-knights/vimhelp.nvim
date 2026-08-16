describe("vimhelp.picker", function()
	local picker

	before_each(function()
		package.loaded["vimhelp.picker"] = nil
		picker = require("vimhelp.picker")
	end)

	--- Build a fake `has_module` that returns true only for the given
	--- module names.
	local function has_only(available)
		local set = {}
		for _, name in ipairs(available) do
			set[name] = true
		end
		return function(name)
			return set[name] == true
		end
	end

	describe("choose", function()
		it("returns 'messages' when preferred = 'messages' regardless of availability", function()
			assert.equals("messages", picker.choose("messages", { has_module = has_only({ "snacks", "telescope" }) }))
		end)

		it("resolves preferred = 'snacks' to snacks when available, else messages", function()
			assert.equals("snacks", picker.choose("snacks", { has_module = has_only({ "snacks" }) }))
			assert.equals("messages", picker.choose("snacks", { has_module = has_only({}) }))
		end)

		it("resolves preferred = 'telescope' to telescope when available, else messages", function()
			assert.equals("telescope", picker.choose("telescope", { has_module = has_only({ "telescope" }) }))
			assert.equals("messages", picker.choose("telescope", { has_module = has_only({}) }))
		end)

		describe("auto fallback order", function()
			it("prefers snacks over telescope when both are loadable", function()
				assert.equals("snacks", picker.choose("auto", { has_module = has_only({ "snacks", "telescope" }) }))
			end)

			it("falls through to telescope when only telescope is loadable", function()
				assert.equals("telescope", picker.choose("auto", { has_module = has_only({ "telescope" }) }))
			end)

			it("falls through to messages when neither picker is loadable", function()
				assert.equals("messages", picker.choose("auto", { has_module = has_only({}) }))
			end)
		end)

		it("defaults to 'auto' when preferred is nil", function()
			assert.equals("messages", picker.choose(nil, { has_module = has_only({}) }))
		end)
	end)

	describe("pick", function()
		it("dispatches to the chosen backend's pick function", function()
			local calls = {}
			local fake_backend = {
				pick = function(result, opts)
					calls[#calls + 1] = { result = result, opts = opts }
				end,
			}
			picker.pick({ query = "q", hits = {} }, { picker = "auto" }, {
				has_module = has_only({}), -- forces "messages" backend
				pickers = { messages = fake_backend },
			})
			assert.equals(1, #calls)
			assert.equals("q", calls[1].result.query)
		end)

		it("forwards opts unchanged to the backend", function()
			local captured_opts
			picker.pick({ query = "q", hits = {} }, { picker = "messages", printer = function() end }, {
				pickers = {
					messages = {
						pick = function(_r, o)
							captured_opts = o
						end,
					},
				},
			})
			-- The dispatcher passes the original opts (with picker + printer)
			-- through unchanged so backends can consume backend-specific keys.
			assert.equals("messages", captured_opts.picker)
			assert.is_function(captured_opts.printer)
		end)
	end)
end)
