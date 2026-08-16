--- Parse and render vimhelp-index search output.
---
--- Split from binary.lua so JSON handling is pure — tests inject stdout
--- strings directly and assert on the shaped table without ever
--- spawning a subprocess.
---
--- Wire shape expected from `vimhelp-index search --format=json`:
--- {
---   "query": string,
---   "hits": [
---     {
---       "document": string,
---       "tag": string | null,
---       "section_header": string | null,
---       "line": integer,
---       "score": number,
---       "snippet": string
---     },
---     ...
---   ]
--- }

local M = {}

--- vim.json.decode maps JSON null to vim.NIL; normalise to Lua nil so
--- callers can write `hit.tag and ...` without a helper. Local so it
--- doesn't leak into the global namespace.
local function normalise_null(v)
	if v == nil or v == vim.NIL then
		return nil
	end
	return v
end

--- Parse the CLI's JSON envelope into a normalised table.
--- @param stdout string Raw stdout from `vimhelp-index search`.
--- @return { query: string, hits: table[] }
function M.parse(stdout)
	assert(type(stdout) == "string", "search.parse: stdout must be a string")
	local ok, decoded = pcall(vim.json.decode, stdout)
	if not ok then
		error("search.parse: invalid JSON from vimhelp-index — " .. tostring(decoded))
	end
	if type(decoded) ~= "table" then
		error("search.parse: expected JSON object, got " .. type(decoded))
	end
	-- Arrays deserialize into Lua tables too — the shape check on
	-- `hits` is what distinguishes the vimhelp-index envelope from
	-- any other JSON that happens to parse.
	if type(decoded.hits) ~= "table" then
		error("search.parse: expected `hits` array in JSON envelope")
	end

	local hits = {}
	for _, raw in ipairs(decoded.hits) do
		hits[#hits + 1] = {
			document = raw.document,
			tag = normalise_null(raw.tag),
			section_header = normalise_null(raw.section_header),
			line = raw.line,
			score = raw.score,
			snippet = raw.snippet,
		}
	end
	return { query = decoded.query, hits = hits }
end

--- Render a parsed search result as a human-readable multi-line string.
--- Stable shape so callers can grep the output; empty hit list renders
--- an actionable "no hits" line.
--- @param result { query: string, hits: table[] }
--- @return string
function M.render(result)
	assert(type(result) == "table", "search.render: result must be a table")
	if #result.hits == 0 then
		return string.format("no hits for %q", result.query or "")
	end

	local lines = {}
	for i, h in ipairs(result.hits) do
		local tag = h.tag or "<no tag>"
		lines[#lines + 1] = string.format("%d. %s  (score %.2f)", i, tag, h.score or 0)
		local header = h.section_header or "<no header>"
		lines[#lines + 1] = string.format("   %s:%d  — %s", h.document or "<no doc>", h.line or 0, header)
		if h.snippet and #h.snippet > 0 then
			lines[#lines + 1] = "   " .. h.snippet
		end
		lines[#lines + 1] = ""
	end
	-- Trim trailing blank so print()/vim.notify don't emit two newlines.
	while #lines > 0 and lines[#lines] == "" do
		lines[#lines] = nil
	end
	return table.concat(lines, "\n")
end

return M
