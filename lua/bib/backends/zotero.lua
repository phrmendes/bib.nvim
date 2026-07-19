local patterns = require("bib.patterns")
local u = require("bib.utils")

local zotero = {}

---@type {entries: table<string, ZoteroEntry>}
local state = {
	entries = {},
}

--- Load state.entries from Zotero SQLite database
---@return nil
function zotero.load()
	local sqlite = require("sqlite")
	local db_path = u.backends.find_zotero_db()
	if not db_path or not vim.uv.fs_stat(db_path) then error("zotero database not found") end

	local db = sqlite.new(db_path)
	db:open()

	local items = db:eval(u.backends.read_sql("items"))
	local creators = db:eval(u.backends.read_sql("creators"))
	db:close()

	if not items or #items == 0 then error("zotero database is empty") end

	state.entries = {}
	local item_to_key = {}

	vim.iter(items):each(function(row)
		local key = row.key
		if not state.entries[key] then state.entries[key] = { key = key, type = row.typeName, fields = {} } end
		state.entries[key].fields[row.fieldName] = row.value
		item_to_key[row.itemID] = key
	end)

	vim.iter(creators or {}):each(function(row)
		local key = item_to_key[row.itemID]
		if not key or not state.entries[key] then return end
		local name = vim.trim((row.firstName or "") .. " " .. (row.lastName or ""))
		local e = state.entries[key]
		local existing = e.creators or {}
		existing[row.creatorType] = existing[row.creatorType] and existing[row.creatorType] .. ", " .. name or name
		e.creators = existing
		if row.creatorType == "author" then e.fields.author = existing[row.creatorType] end
	end)

	vim.iter(pairs(state.entries)):each(function(itemID, entry)
		local citekey = entry.fields.citationKey

		if citekey then
			entry.key = itemID .. "#" .. citekey
			entry.citekey = citekey
		else
			entry.key = itemID .. "#" .. itemID
			entry.citekey = itemID
		end

		entry.zotkey = itemID

		if entry.fields.date then entry.fields.year = entry.fields.date:match(patterns.year) end
	end)
end

--- Get state.entries matching a prefix (case-insensitive, matches citekey)
---@param prefix string
---@return ZoteroEntry[]
function zotero.match(prefix)
	local lower = prefix:lower()
	return vim.iter(pairs(state.entries)):filter(function(_, e) return e.citekey:lower():find(lower, 1, true) == 1 end):map(function(_, e) return e end):totable()
end

--- Search entries by substring (case-insensitive, matches citekey/title/author)
---@param query string
---@return ZoteroEntry[]
function zotero.search(query)
	local lower = query:lower()
	return vim
		.iter(pairs(state.entries))
		:filter(function(_, e)
			if e.citekey:lower():find(lower, 1, true) then return true end
			if e.fields.title and e.fields.title:lower():find(lower, 1, true) then return true end
			if e.fields.author and e.fields.author:lower():find(lower, 1, true) then return true end
			return false
		end)
		:map(function(_, e) return e end)
		:totable()
end

--- Get a single entry by composite key
---@param key string
---@return ZoteroEntry|nil
function zotero.get(key) return state.entries[key:gsub(patterns.zotkey_strip, "")] end

--- Get all entries
---@return ZoteroEntry[]
function zotero.all()
	return vim.iter(pairs(state.entries)):map(function(_, e) return e end):totable()
end

--- Get go-to-definition URI for a key
---@param key string
---@return {uri: string, range: table}|nil
function zotero.definition(key)
	local zotkey = key:gsub(patterns.zotkey_strip, "")
	if not state.entries[zotkey] then return nil end
	return { uri = "zotero://select/library/items/" .. zotkey }
end

--- Get hover content for a key
---@param key string
---@return string|nil
function zotero.hover(key)
	local zotkey = key:gsub(patterns.zotkey_strip, "")
	local entry = state.entries[zotkey]
	if not entry then return nil end
	local header = {}
	if entry.creators and entry.creators.author then table.insert(header, entry.creators.author) end
	if entry.fields.title then table.insert(header, entry.fields.title) end
	if entry.fields.date then
		local year = entry.fields.date:match(patterns.year)
		table.insert(header, year or entry.fields.date)
	end
	local parts = { "# " .. table.concat(header, " - ") }
	if entry.fields.abstractNote then
		local abstract = entry.fields.abstractNote:gsub(patterns.whitespace, " ")
		table.insert(parts, "---\n" .. abstract)
	end
	return table.concat(parts, "\n\n")
end

return zotero
