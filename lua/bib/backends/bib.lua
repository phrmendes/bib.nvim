local patterns = require("bib.patterns")
local query = require("bib.query")
local utils = require("bib.utils")
local queries = require("bib.queries")

---@class BibEntry
---@field key string The citation key
---@field type string The entry type (article, book, etc.)
---@field fields table<string, string> Field name -> value
---@field line integer Line number in the .bib file (1-indexed)

local bib = {}

---@type table<string, BibEntry>|nil
local entries = nil

---@type string|nil
local bib_path = nil

--- Extract @string macros from the AST
---@param buf integer
---@param root TSNode
---@return table<string, string>
local function collect_strings(buf, root)
	local ids = query.capture_ids(queries.bibtex_strings)
	local matches = queries.bibtex_strings:iter_matches(root, buf, 0, -1)
	return vim.iter(matches):fold({}, function(strings, _, match)
		local name_node = match[ids["name"]][1]
		local value_node = match[ids["value"]][1]
		if not name_node or not value_node then return strings end
		local name = vim.trim(vim.treesitter.get_node_text(name_node, buf))
		local value = utils.strip_value(vim.treesitter.get_node_text(value_node, buf))
		if name ~= "" then strings[name] = value end
		return strings
	end)
end

--- Extract entries from the AST
---@param buf integer
---@param root TSNode
---@param strings table<string, string>
---@return table<string, BibEntry>
local function collect_entries(buf, root, strings)
	local ids = query.capture_ids(queries.bibtex_entries)
	local matches = queries.bibtex_entries:iter_matches(root, buf, 0, -1)
	return vim.iter(matches):fold({}, function(result, _, match)
		local type_node = match[ids["type"]][1]
		local key_node = match[ids["key"]][1]
		local name_node = match[ids["name"]][1]
		local value_node = match[ids["value"]][1]

		if not type_node or not key_node or not name_node or not value_node then return result end
		local key = vim.treesitter.get_node_text(key_node, buf)
		local fname = vim.trim(vim.treesitter.get_node_text(name_node, buf)):lower()
		local fvalue = utils.resolve_value(vim.treesitter.get_node_text(value_node, buf), strings)

		if result[key] then
			result[key].fields[fname] = fvalue
			return result
		end

		local etype = vim.treesitter.get_node_text(type_node, buf):sub(2):lower()

		result[key] = {
			key = key,
			type = etype,
			fields = { [fname] = fvalue },
			line = type_node:start() + 1,
		}
		return result
	end)
end

--- Parse a .bib file using tree-sitter
---@param path string
---@return table<string, BibEntry>|nil
local function parse(path)
	local buf = vim.fn.bufadd(path)
	vim.fn.bufload(buf)

	local parser = vim.treesitter.get_parser(buf, "bibtex")
	if not parser then
		vim.api.nvim_buf_delete(buf, { force = true })
		return nil
	end

	local root = parser:parse()[1]:root()
	local strings = collect_strings(buf, root)
	local result = collect_entries(buf, root, strings)

	vim.api.nvim_buf_delete(buf, { force = true })
	return result
end

--- Load entries from the .bib file for a buffer
---@param bufnr integer
---@return boolean
function bib.load(bufnr)
	local found = utils.find_bib_file(bufnr)
	if not found then return false end

	local parsed = parse(found)
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
	if not entries then return {} end
	local lower = prefix:lower()
	return vim.iter(pairs(entries)):filter(function(key) return key:lower():find(lower, 1, true) == 1 end):map(function(_, entry) return entry end):totable()
end

--- Get a single entry by key
---@param key string
---@return BibEntry|nil
function bib.get(key)
	if not entries then return nil end
	return entries[key]
end

--- Get go-to-definition location for a key
---@param key string
---@return {uri: string, range: table}|nil
function bib.definition(key)
	if not entries or not bib_path then return nil end
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
	if not entries then return nil end
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
