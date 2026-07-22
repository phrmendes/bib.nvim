local format_item = require("bib.utils").format_item
local handle_selection = require("bib.utils").handle_selection
local load = require("bib.utils.backends").load

---@type table
local commands = {}

--- Search bib (or zotero) and open reference
---@param args string
function commands.search(args)
	local zotero_only = vim.trim(args or "") == "zotero"

	vim.schedule(function()
		local raw = zotero_only and load.zotero() or load.bib() or load.zotero()

		if not raw or #raw == 0 then
			vim.notify("No entries found", vim.log.levels.INFO)
			return
		end

		local items = vim.iter(raw):map(function(e) return { display = format_item(e), key = e.key, zotkey = e.zotkey } end):totable()

		vim.ui.select(items, {
			prompt = "References:",
			format_item = function(v) return v.display end,
		}, handle_selection)
	end)
end

return commands
