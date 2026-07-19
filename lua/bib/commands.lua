---@type table
local commands = {}

--- Search bib (or zotero with backend=zotero) and insert citation key
---@param args string
function commands.search(args)
	args = vim.trim(args or "")

	local backend = nil
	local query = args

	if args:match("^backend=zotero%s") then
		backend = "zotero"
		query = args:gsub("^backend=zotero%s+", "")
	elseif args == "backend=zotero" then
		backend = "zotero"
		query = ""
	end

	if query == "" then
		local prompt = backend == "zotero" and "Zotero search: " or "Search: "
		vim.ui.input({ prompt = prompt }, function(input)
			if not input or input == "" then return end
			commands.search((backend and "backend=zotero " or "") .. input)
		end)
		return
	end

	vim.schedule(function()
		local items = {}

		if backend == "zotero" then
			local zotero = require("bib.backends.zotero")
			local ok = pcall(zotero.load)

			if not ok then
				vim.notify("Zotero: failed to load database", vim.log.levels.ERROR)
				return
			end

			items = zotero.search(query)
		else
			local bib = require("bib.backends.bib")
			items = bib.search(query)

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
				local label = string.format("%s  %s", e.citekey or e.key, e.fields.title or "")
				if e.fields.author then label = label .. "  (" .. e.fields.author .. ")" end
				if #label > 100 then label = label:sub(1, 97) .. "..." end
				return label
			end,
		}, function(entry)
			if not entry then return end
			vim.api.nvim_put({ entry.citekey or entry.key }, "c", true)
		end)
	end)
end

return commands
