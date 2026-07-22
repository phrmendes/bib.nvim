---@type table
local utils = {}
local p = require("bib.patterns")

--- Prefer citekey over key for display
---@param entry table
---@return string
function utils.display_key(entry) return entry.citekey or entry.key end

--- Format entry for picker display: author - title
---@param e table
---@return string
function utils.format_item(e)
	local author = e.creators and e.creators.author or e.fields.author or "?"
	local authors = vim.split(author, ", ")
	local lastnames = vim.iter(authors):map(function(a) return a:match(p.lastname) or a end):totable()

	if #lastnames > 2 then
		author = lastnames[1] .. " et al"
	else
		author = table.concat(lastnames, ", ")
	end

	if e.fields.year then author = author .. " (" .. e.fields.year .. ")" end

	local title = e.fields.title or "Untitled"
	return string.format("%s - %s", author, title)
end

--- Dispatch selected entry to the right action (zotero URI or LSP jump)
---@param item {display: string, key: string?, zotkey: string?}|nil
function utils.handle_selection(item)
	if not item then return end

	if item.zotkey then
		vim.ui.open("zotero://select/library/items/" .. item.zotkey)
		return
	end

	if item.key then
		local loc = require("bib.backends.bib").definition(item.key)
		if loc then vim.lsp.util.show_document({ uri = loc.uri, selection = loc.range }, nil, { focus = true }) end
	end
end

return utils
