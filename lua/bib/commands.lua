local p = require("bib.patterns")
local u = require("bib.utils")

---@type table
local commands = {}

--- Search bib (or zotero) and open or insert citation key
---@param args string
function commands.search(args)
	args = vim.trim(args or "")

	local zotero_only = false
	local query = args

	if args:find(p.search_zotero) == 1 then
		zotero_only = true
		query = args:gsub(p.search_zotero, "", 1)
	elseif args == "zotero" then
		zotero_only = true
		query = ""
	end

	if query == "" then
		local prompt = zotero_only and "Zotero search: " or "Search: "
		vim.ui.input({ prompt = prompt }, function(input)
			if not input or input == "" then return end
			commands.search((zotero_only and "zotero " or "") .. input)
		end)
		return
	end

	vim.schedule(function()
		local items = {}

		if zotero_only then
			local zotero = require("bib.backends.zotero")
			local ok = pcall(zotero.load)

			if not ok then
				vim.notify("Zotero: failed to load database", vim.log.levels.ERROR)
				return
			end

			items = zotero.search(query)
		else
			local bib = require("bib.backends.bib")
			local ok = pcall(bib.load, vim.api.nvim_get_current_buf())
			if ok then items = bib.search(query) end

			if #items == 0 then
				local zotero = require("bib.backends.zotero")
				local ok = pcall(zotero.load)

				if ok then items = zotero.search(query) end
			end
		end

		if #items == 0 then
			vim.notify("No entries found for: " .. query, vim.log.levels.INFO)
			return
		end

		vim.ui.select(items, {
			prompt = "Results:",
			format_item = function(e)
				local label = string.format("%s  %s", u.display_key(e), e.fields.title or "")
				if e.fields.author then label = label .. "  (" .. e.fields.author .. ")" end
				if #label > 100 then label = label:sub(1, 97) .. "..." end
				return label
			end,
		}, function(entry)
			if not entry then return end

			if entry.zotkey then
				vim.ui.open("zotero://select/library/items/" .. entry.zotkey)
			else
				local bib = require("bib.backends.bib")
				local loc = bib.definition(entry.key)
				if loc then vim.lsp.util.jump_to_location(loc) end
			end
		end)
	end)
end

return commands
