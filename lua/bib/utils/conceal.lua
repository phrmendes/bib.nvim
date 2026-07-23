local p = require("bib.patterns")

---@type table
local conceal = {}

--- Collect extmark specs from a line for @ITEMID#citekey (Zotero) and @citekey (bib) patterns
---@param line string
---@return table[] marks Array of {col: integer, opts: table} specs
function conceal.collect_marks(line)
	return vim.iter(line:gmatch(p.conceal_scan)):fold({}, function(marks, pos, key)
		local at_col = pos - 1
		local hash = key:find("#", 1, true)

		marks[#marks + 1] = { col = at_col, opts = { end_col = at_col + 1, hl_group = "BibCitePrefix" } }

		if hash then
			marks[#marks + 1] = { col = at_col + 1, opts = { end_col = at_col + hash + 1, conceal = "", hl_group = "BibCitePrefix" } }
			local citekey = key:sub(hash + 1)
			if citekey ~= "" then marks[#marks + 1] = { col = at_col + hash + 1, opts = { end_col = at_col + hash + 1 + #citekey, hl_group = "BibCiteKey" } } end
		else
			marks[#marks + 1] = { col = at_col + 1, opts = { end_col = at_col + 1 + #key, hl_group = "BibCiteKey" } }
		end

		return marks
	end)
end

return conceal
