local patterns = require("bib.patterns")
local u = require("bib.utils")

local bib = {}

---@type {entries: table<string, BibEntry>, path: string|nil}
local state = {
	entries = {},
	path = nil,
}

--- Load state.entries from the .bib file for a buffer
---@param bufnr integer
---@return nil
function bib.load(bufnr)
	local found = u.backends.find_bib_file(bufnr)
	if not found then error("no .bib file found for buffer " .. bufnr) end

	local parsed = u.backends.parse(found)
	if not parsed then error("failed to parse " .. found) end

	state.path = found
	state.entries = parsed
end

--- Get state.entries matching a prefix (case-insensitive)
---@param prefix string
---@return BibEntry[]
function bib.match(prefix)
	local lower = prefix:lower()
	return vim.iter(pairs(state.entries)):filter(function(key) return key:lower():find(lower, 1, true) == 1 end):map(function(_, entry) return entry end):totable()
end

--- Get a single entry by key
---@param key string
---@return BibEntry|nil
function bib.get(key) return state.entries[key] end

--- Get all entries
---@return BibEntry[]
function bib.all()
	return vim.iter(pairs(state.entries)):map(function(_, e) return e end):totable()
end

--- Search entries by substring (case-insensitive, matches key/title/author)
---@param query string
---@return BibEntry[]
function bib.search(query)
	local lower = query:lower()
	return vim
		.iter(pairs(state.entries))
		:filter(function(_, e)
			if e.key:lower():find(lower, 1, true) then return true end
			if e.fields.title and e.fields.title:lower():find(lower, 1, true) then return true end
			if e.fields.author and e.fields.author:lower():find(lower, 1, true) then return true end
			return false
		end)
		:map(function(_, e) return e end)
		:totable()
end

--- Get go-to-definition location for a key
---@param key string
---@return {uri: string, range: table}|nil
function bib.definition(key)
	if not state.path then return nil end
	local entry = state.entries[key]
	if not entry then return nil end
	return {
		uri = vim.uri_from_fname(state.path),
		range = {
			start = { line = entry.line - 1, character = 0 },
			["end"] = { line = entry.line - 1, character = 0 },
		},
	}
end

--- Get hover content for a key
---@param key string
---@return string|nil
function bib.hover(key)
	local entry = state.entries[key]
	if not entry then return nil end
	local header = {}
	if entry.fields.author then table.insert(header, entry.fields.author) end
	if entry.fields.title then table.insert(header, entry.fields.title) end
	if entry.fields.year then table.insert(header, entry.fields.year) end
	local parts = { "# " .. table.concat(header, " - ") }
	if entry.fields.abstract then
		local abstract = entry.fields.abstract:gsub(patterns.whitespace, " ")
		table.insert(parts, "---\n" .. abstract)
	end
	return table.concat(parts, "\n\n")
end

return bib
