describe("vimhelp.search", function()
	local search

	before_each(function()
		package.loaded["vimhelp.search"] = nil
		search = require("vimhelp.search")
	end)

	describe("parse", function()
		it("parses the vimhelp-index JSON envelope shape", function()
			local json = vim.json.encode({
				query = "floating window",
				hits = {
					{
						document = "doc/api.txt",
						tag = "nvim_open_win",
						section_header = "3.2 Window functions",
						line = 1287,
						score = 3.42,
						snippet = "Opens a new floating window.",
					},
				},
			})

			local r = search.parse(json)

			assert.equals("floating window", r.query)
			assert.equals(1, #r.hits)
			assert.equals("doc/api.txt", r.hits[1].document)
			assert.equals("nvim_open_win", r.hits[1].tag)
			assert.equals("3.2 Window functions", r.hits[1].section_header)
			assert.equals(1287, r.hits[1].line)
			assert.equals("Opens a new floating window.", r.hits[1].snippet)
		end)

		it("normalises JSON null on tag / section_header to Lua nil", function()
			-- vim.json.decode maps JSON null to vim.NIL; callers should
			-- get plain nil so `hit.tag and ...` works.
			local json =
				'{"query":"q","hits":[{"document":"d","tag":null,"section_header":null,"line":1,"score":0.1,"snippet":""}]}'
			local r = search.parse(json)
			assert.is_nil(r.hits[1].tag)
			assert.is_nil(r.hits[1].section_header)
		end)

		it("handles the empty-hits case", function()
			local json = '{"query":"nope","hits":[]}'
			local r = search.parse(json)
			assert.equals("nope", r.query)
			assert.equals(0, #r.hits)
		end)

		it("errors with an actionable message on invalid JSON", function()
			assert.has_error(function()
				search.parse("not json at all")
			end)
		end)

		it("errors when the top-level shape is not an object", function()
			assert.has_error(function()
				search.parse("[1, 2, 3]")
			end)
		end)

		it("rejects non-string input at the boundary", function()
			assert.has_error(function()
				---@diagnostic disable-next-line: param-type-mismatch
				search.parse(42)
			end)
		end)
	end)

	describe("render", function()
		it("returns 'no hits' when the hit list is empty", function()
			local out = search.render({ query = "floating", hits = {} })
			assert.equals('no hits for "floating"', out)
		end)

		it("ranks hits 1-indexed with score, path:line, header, snippet", function()
			local out = search.render({
				query = "q",
				hits = {
					{
						document = "doc/a.txt",
						tag = "tag-one",
						section_header = "S1",
						line = 12,
						score = 2.35,
						snippet = "body one",
					},
					{
						document = "doc/b.txt",
						tag = "tag-two",
						section_header = "S2",
						line = 42,
						score = 1.10,
						snippet = "body two",
					},
				},
			})
			assert.is_truthy(out:match("1%. tag%-one%s+%(score 2%.35%)"))
			assert.is_truthy(out:match("doc/a%.txt:12%s+— S1"))
			assert.is_truthy(out:match("body one"))
			assert.is_truthy(out:match("2%. tag%-two%s+%(score 1%.10%)"))
		end)

		it("substitutes friendly placeholders for missing tag / header", function()
			local out = search.render({
				query = "q",
				hits = {
					{
						document = "doc/x.txt",
						tag = nil,
						section_header = nil,
						line = 1,
						score = 0.1,
						snippet = "s",
					},
				},
			})
			assert.is_truthy(out:match("<no tag>"))
			assert.is_truthy(out:match("<no header>"))
		end)

		it("skips the snippet line when the snippet is empty", function()
			local out = search.render({
				query = "q",
				hits = {
					{
						document = "d",
						tag = "t",
						section_header = "h",
						line = 1,
						score = 0.1,
						snippet = "",
					},
				},
			})
			-- Three parts should appear: rank line, path line, but NO snippet
			-- indent line. Assert by counting the indent prefix "   " lines.
			local indented = select(2, out:gsub("\n   ", ""))
			assert.equals(1, indented) -- only the path:line row is indented
		end)

		it("does not leave a trailing blank line after the last hit", function()
			local out = search.render({
				query = "q",
				hits = {
					{ document = "d", tag = "t", section_header = "h", line = 1, score = 0.1, snippet = "s" },
				},
			})
			assert.is_false(out:sub(-1) == "\n")
		end)

		it("rejects a non-table result at the boundary", function()
			assert.has_error(function()
				---@diagnostic disable-next-line: param-type-mismatch
				search.render("nope")
			end)
		end)
	end)
end)
