local bib_utils = require("bib.backends.utils")
local patterns = require("bib.patterns")
local utils = require("bib.utils")

---@class BibEntry
---@field key string The citation key
---@field type string The entry type (article, book, etc.)
---@field fields table<string, string> Field name -> value
---@field line integer Line number in the .bib file (1-indexed)

local bib = {}

---@type table<string, BibEntry>
local entries = {}

---@type string|nil
local bib_path = nil

--- Load entries from the .bib file for a buffer
---@param bufnr integer
---@return boolean
function bib.load(bufnr)
	local found = utils.find_bib_file(bufnr)
	if not found then return false end

	local parsed = bib_utils.parse(found)
	if not parsed then
		vim.notify("bib.nvim: failed to parse " .. found, vim.log.levels.WARN)
		return false
	end

	bib_path = found
	entries = parsed
	return true
end

--- Get entries matching a prefix (case-insensitive)
---@param prefix string
---@return BibEntry[]
function bib.match(prefix)
	local lower = prefix:lower()
	return vim.iter(pairs(entries)):filter(function(key) return key:lower():find(lower, 1, true) == 1 end):map(function(_, entry) return entry end):totable()
end

--- Get a single entry by key
---@param key string
---@return BibEntry|nil
function bib.get(key) return entries[key] end

--- Get go-to-definition location for a key
---@param key string
---@return {uri: string, range: table}|nil
function bib.definition(key)
	if not bib_path then return nil end
	local entry = entries[key]
	if not entry then return nil end
	return {
		uri = vim.uri_from_fname(bib_path),
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
	local entry = entries[key]
	if not entry then return nil end
	local parts = {}
	if entry.fields.author then table.insert(parts, "# Author\n" .. entry.fields.author) end
	if entry.fields.title then table.insert(parts, "# Title\n" .. entry.fields.title) end
	if entry.fields.year then table.insert(parts, "# Year\n" .. entry.fields.year) end
	if entry.fields.journal then table.insert(parts, "# Journal\n" .. entry.fields.journal) end
	if entry.fields.booktitle then table.insert(parts, "# Book\n" .. entry.fields.booktitle) end
	if entry.fields.abstract then
		local abstract = entry.fields.abstract:gsub(patterns.whitespace, " ")
		table.insert(parts, "---\n" .. abstract)
	end
	return table.concat(parts, "\n\n")
end

return bib
