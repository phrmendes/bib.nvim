local backend_utils = require("bib.backends.utils")
local patterns = require("bib.patterns")
local sqlite = require("sqlite")
local utils = require("bib.utils")

local zotero = {}

---@class ZoteroEntry
---@field key string Composite key (itemID#citekey)
---@field zotkey string Zotero item key
---@field type string Entry type (journalArticle, book, etc.)
---@field fields table<string, string> Field name -> value
---@field creators table<string, string> Creator type -> comma-separated names

---@type table<string, ZoteroEntry>
local entries = {}

--- Load entries from Zotero SQLite database
---@return boolean
function zotero.load()
	local db_path = utils.find_zotero_db()
	if not db_path or not vim.uv.fs_stat(db_path) then return false end

	local db = sqlite.new(db_path)
	db:open()

	local items = db:eval(backend_utils.read_sql("items"))
	local creators = db:eval(backend_utils.read_sql("creators"))
	db:close()

	if not items or #items == 0 then return false end

	entries = {}
	local item_to_key = {}

	vim.iter(items):each(function(row)
		local key = row.key
		if not entries[key] then entries[key] = { key = key, type = row.typeName, fields = {} } end
		entries[key].fields[row.fieldName] = row.value
		item_to_key[row.itemID] = key
	end)

	vim.iter(creators or {}):each(function(row)
		local key = item_to_key[row.itemID]
		if not key or not entries[key] then return end
		local name = vim.trim((row.firstName or "") .. " " .. (row.lastName or ""))
		local e = entries[key]
		local existing = e.creators or {}
		existing[row.creatorType] = existing[row.creatorType] and existing[row.creatorType] .. ", " .. name or name
		e.creators = existing
		if row.creatorType == "author" then e.fields.author = existing[row.creatorType] end
	end)

	vim.iter(pairs(entries)):each(function(itemID, entry)
		local citekey = entry.fields.citationKey

		if citekey then
			entry.key = itemID .. "#" .. citekey
			entry.citekey = citekey
		else
			entry.key = itemID .. "#" .. itemID
			entry.citekey = itemID
		end

		entry.zotkey = itemID
	end)

	return true
end

--- Get entries matching a prefix (case-insensitive, matches citekey)
---@param prefix string
---@return ZoteroEntry[]
function zotero.match(prefix)
	local lower = prefix:lower()
	return vim.iter(pairs(entries)):filter(function(_, e) return e.citekey:lower():find(lower, 1, true) == 1 end):map(function(_, e) return e end):totable()
end

--- Get a single entry by composite key
---@param key string
---@return ZoteroEntry|nil
function zotero.get(key) return entries[key:gsub("#.*", "")] end

--- Get go-to-definition URI for a key
---@param key string
---@return {uri: string, range: table}|nil
function zotero.definition(key)
	local zotkey = key:gsub("#.*", "")
	if not entries[zotkey] then return nil end
	return { uri = "zotero://select/library/items/" .. zotkey }
end

--- Get hover content for a key
---@param key string
---@return string|nil
function zotero.hover(key)
	local zotkey = key:gsub("#.*", "")
	local entry = entries[zotkey]
	if not entry then return nil end
	local parts = {}
	if entry.creators and entry.creators.author then table.insert(parts, "# Author\n" .. entry.creators.author) end
	if entry.fields.title then table.insert(parts, "# Title\n" .. entry.fields.title) end
	if entry.fields.date then table.insert(parts, "# Year\n" .. entry.fields.date) end
	if entry.fields.abstractNote then
		local abstract = entry.fields.abstractNote:gsub(patterns.whitespace, " ")
		table.insert(parts, "---\n" .. abstract)
	end
	return table.concat(parts, "\n\n")
end

return zotero
