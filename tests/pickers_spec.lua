describe("vimhelp.pickers.messages", function()
	local messages
	before_each(function()
		package.loaded["vimhelp.pickers.messages"] = nil
		package.loaded["vimhelp.search"] = nil
		messages = require("vimhelp.pickers.messages")
	end)

	it("routes the rendered result through the injected printer", function()
		local captured
		messages.pick({ query = "q", hits = {} }, {
			printer = function(text)
				captured = text
			end,
		})
		-- Rendered "no hits" line, straight from search.render.
		assert.equals('no hits for "q"', captured)
	end)

	it("renders every hit's tag and score into the printed text", function()
		local captured
		messages.pick({
			query = "q",
			hits = {
				{
					document = "doc/a.txt",
					tag = "alpha",
					section_header = "Header A",
					line = 1,
					score = 1.5,
					snippet = "body",
				},
			},
		}, {
			printer = function(text)
				captured = text
			end,
		})
		assert.is_truthy(captured:match("1%. alpha"))
		assert.is_truthy(captured:match("score 1%.50"))
	end)
end)

describe("vimhelp.pickers.snacks", function()
	local snacks_adapter
	before_each(function()
		package.loaded["vimhelp.pickers.snacks"] = nil
		snacks_adapter = require("vimhelp.pickers.snacks")
	end)

	describe("item_for (pure shape)", function()
		it("packs the domain hit alongside a formatted text line", function()
			local hit = {
				document = "doc/a.txt",
				tag = "alpha",
				section_header = "Header A",
				line = 42,
				score = 1.5,
				snippet = "body",
			}
			local item = snacks_adapter.item_for(hit)
			-- hit round-trips so confirm() can jump to it.
			assert.equals(hit, item.hit)
			-- text contains tag + path:line + header.
			assert.is_truthy(item.text:match("alpha"))
			assert.is_truthy(item.text:match("doc/a%.txt:42"))
			assert.is_truthy(item.text:match("Header A"))
		end)

		it("substitutes placeholders for missing tag / header", function()
			local item = snacks_adapter.item_for({ document = "d", line = 1 })
			assert.is_truthy(item.text:match("<no tag>"))
			assert.is_truthy(item.text:match("<no header>"))
		end)
	end)

	it("passes items and confirm to the injected snacks fake, jump fires on confirm", function()
		local captured
		local fake_snacks = {
			picker = {
				pick = function(spec)
					captured = spec
				end,
			},
		}
		local jumped
		snacks_adapter.pick({
			query = "q",
			hits = {
				{
					document = "d.txt",
					tag = "t",
					section_header = "h",
					line = 3,
					score = 1,
					snippet = "s",
				},
			},
		}, {
			snacks = fake_snacks,
			jump = function(hit)
				jumped = hit
			end,
		})
		assert.equals(1, #captured.items)
		assert.equals("t", captured.items[1].hit.tag)
		-- Simulate a snacks confirm event on the first item.
		local fake_picker = {
			close = function() end,
		}
		captured.confirm(fake_picker, captured.items[1])
		assert.equals("t", jumped.tag)
	end)

	it("format() returns a snacks-shaped highlight fragment", function()
		local captured
		snacks_adapter.pick({ query = "q", hits = {} }, {
			snacks = {
				picker = {
					pick = function(spec)
						captured = spec
					end,
				},
			},
			jump = function() end,
		})
		local fragment = captured.format({ text = "row" })
		-- snacks format returns { {text, highlight_group}, ... }
		assert.equals("row", fragment[1][1])
		assert.equals("SnacksPickerLabel", fragment[1][2])
	end)

	it("errors with an actionable message when snacks is not loadable", function()
		-- No deps.snacks and snacks isn't actually installed in the test env.
		assert.has_error(function()
			snacks_adapter.pick({ query = "q", hits = {} }, {})
		end)
	end)
end)

describe("vimhelp.pickers.telescope", function()
	local telescope_adapter
	before_each(function()
		package.loaded["vimhelp.pickers.telescope"] = nil
		telescope_adapter = require("vimhelp.pickers.telescope")
	end)

	describe("entry_for (pure shape)", function()
		it("produces {value, display, ordinal} with all three tag/header/document searchable", function()
			local hit = { document = "doc/a.txt", tag = "alpha", section_header = "Header A", line = 42 }
			local entry = telescope_adapter.entry_for(hit)
			assert.equals(hit, entry.value)
			assert.is_truthy(entry.display:match("alpha"))
			assert.is_truthy(entry.display:match("doc/a%.txt:42"))
			-- ordinal is the fuzzy-match key; must contain all three so any
			-- of them is a valid filter term.
			assert.is_truthy(entry.ordinal:match("alpha"))
			assert.is_truthy(entry.ordinal:match("Header A"))
			assert.is_truthy(entry.ordinal:match("doc/a%.txt"))
		end)
	end)

	it("wires the entries + finder + sorter into a telescope pickers.new().find() call", function()
		local captured_opts
		local finder_returned = { fake = "finder" }
		local sorter_used = { fake = "sorter" }
		local found = false
		local fake_telescope = {
			pickers = {
				new = function(_layout, opts)
					captured_opts = opts
					return {
						find = function()
							found = true
						end,
					}
				end,
			},
			finders = {
				new_table = function(spec)
					-- entry_maker MUST return the pre-shaped entry unchanged.
					local out = spec.entry_maker(spec.results[1])
					assert.equals(spec.results[1], out)
					return finder_returned
				end,
			},
			sorter = sorter_used,
			actions = {
				select_default = { replace = function(_fn) end },
				close = function() end,
			},
			state = { get_selected_entry = function() end },
		}
		telescope_adapter.pick({
			query = "q",
			hits = { { document = "d", tag = "t", section_header = "h", line = 1 } },
		}, {
			telescope = fake_telescope,
			jump = function() end,
		})
		assert.is_true(found)
		assert.equals("vimhelp: q", captured_opts.prompt_title)
		assert.equals(finder_returned, captured_opts.finder)
		assert.equals(sorter_used, captured_opts.sorter)
	end)

	it("attach_mappings wires the select action to jump with the selected value", function()
		local replaced_fn
		local jumped
		local fake_selection = { value = { tag = "chosen" } }
		local fake_telescope = {
			pickers = {
				new = function(_layout, opts)
					opts.attach_mappings(999, function() end)
					return { find = function() end }
				end,
			},
			finders = {
				new_table = function()
					return {}
				end,
			},
			sorter = {},
			actions = {
				-- telescope's select_default:replace(fn) is colon-called, so
				-- the first arg here is `self` (the select_default table)
				-- and `fn` is the callback the adapter installed.
				select_default = {
					replace = function(_self, fn)
						replaced_fn = fn
					end,
				},
				close = function(_bufnr) end,
			},
			state = {
				get_selected_entry = function()
					return fake_selection
				end,
			},
		}
		telescope_adapter.pick({
			query = "q",
			hits = { { document = "d", tag = "t", section_header = "h", line = 1 } },
		}, {
			telescope = fake_telescope,
			jump = function(hit)
				jumped = hit
			end,
		})
		-- Simulate the user hitting <CR>: telescope invokes the replaced
		-- select action, which should call our jump with the selection value.
		assert.is_function(replaced_fn)
		replaced_fn()
		assert.equals("chosen", jumped.tag)
	end)

	it("errors with an actionable message when telescope is not loadable", function()
		assert.has_error(function()
			telescope_adapter.pick({ query = "q", hits = {} }, {})
		end)
	end)
end)
