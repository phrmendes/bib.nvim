local patterns = require("bib.patterns")
local find_bib_file = require("bib.utils.backends").find_bib_file
local parse = require("bib.utils.backends").parse

---@type table
local bib = {}

---@type {entries: table<string, BibEntry>, path: string, default: string}
local state = { entries = {}, default = "references.bib" }

--- Load state.entries from the .bib file for a buffer
---@param bufnr integer
---@return nil
function bib.load(bufnr)
	local bufname = vim.api.nvim_buf_get_name(bufnr)
	local dir = bufname ~= "" and vim.fn.fnamemodify(bufname, ":p:h") or vim.fn.getcwd()
	local found = find_bib_file(bufnr) or vim.fn.fnamemodify(dir .. "/" .. state.default, ":p")
	local parsed = parse(found)

	state.path = found
	state.entries = parsed or {}
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
	if not state.path then return end

	local entry = state.entries[key]
	if not entry then return end

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
	if not entry then return end

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
