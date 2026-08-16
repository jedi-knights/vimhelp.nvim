describe("vimhelp.jump", function()
	local jump

	before_each(function()
		package.loaded["vimhelp.jump"] = nil
		jump = require("vimhelp.jump")
	end)

	-- Build a deps table that captures every side-effect the jump would
	-- otherwise apply to the real editor.
	local function capture()
		local cmds = {}
		local cursors = {}
		return {
			cmd = function(c)
				cmds[#cmds + 1] = c
			end,
			cursor = function(win, pos)
				cursors[#cursors + 1] = { win = win, pos = pos }
			end,
		}, function()
			return cmds, cursors
		end
	end

	it("runs `:help <tag>` when the hit has a tag", function()
		local deps, get = capture()
		jump.to_hit({ tag = "nvim_open_win", document = "d", line = 1 }, deps)
		local cmds, cursors = get()
		assert.equals(1, #cmds)
		assert.is_truthy(cmds[1]:match("^help nvim_open_win$"))
		-- Cursor should NOT be set — :help positions itself.
		assert.equals(0, #cursors)
	end)

	it("edits the document + moves cursor when there's no tag", function()
		local deps, get = capture()
		jump.to_hit({ document = "doc/api.txt", line = 42 }, deps)
		local cmds, cursors = get()
		assert.equals(1, #cmds)
		assert.is_truthy(cmds[1]:match("^edit doc/api%.txt$"))
		assert.equals(1, #cursors)
		assert.same({ 42, 0 }, cursors[1].pos)
	end)

	it("treats empty-string tag as absent (falls through to document)", function()
		local deps, get = capture()
		jump.to_hit({ tag = "", document = "d.txt", line = 3 }, deps)
		local cmds = get()
		assert.is_truthy(cmds[1]:match("^edit d%.txt$"))
	end)

	it("skips the cursor set when line is missing or non-positive", function()
		local deps, get = capture()
		jump.to_hit({ document = "d.txt" }, deps)
		local _, cursors = get()
		assert.equals(0, #cursors)

		local deps2, get2 = capture()
		jump.to_hit({ document = "d.txt", line = 0 }, deps2)
		local _, cursors2 = get2()
		assert.equals(0, #cursors2)
	end)

	it("fnameescape-wraps document paths so spaces don't break :edit", function()
		local deps, get = capture()
		jump.to_hit({ document = "path with spaces.txt", line = 1 }, deps)
		local cmds = get()
		-- fnameescape escapes spaces as `\ ` inside the command.
		assert.is_truthy(cmds[1]:match("path\\ with\\ spaces%.txt"))
	end)

	it("errors when the hit has neither tag nor document", function()
		local deps = capture()
		assert.has_error(function()
			jump.to_hit({}, deps)
		end)
	end)

	it("rejects a non-table hit at the boundary", function()
		assert.has_error(function()
			---@diagnostic disable-next-line: param-type-mismatch
			jump.to_hit("not a table")
		end)
	end)
end)
