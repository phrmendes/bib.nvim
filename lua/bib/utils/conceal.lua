local patterns = require("bib.patterns")

---@type table
local conceal = {}

--- Collect extmark specs from a line for all @ITEMID#citekey conceal patterns
---@param line string
---@return table[] marks Array of {col: integer, opts: table} specs
function conceal.collect_marks(line)
	return vim.iter(line:gmatch("()(" .. patterns.conceal_prefix .. ")")):fold({}, function(marks, pos, prefix)
		local prefix_end = pos + #prefix - 1
		marks[#marks + 1] = { col = pos - 1, opts = { end_col = pos, hl_group = "BibCitePrefix" } }
		marks[#marks + 1] = { col = pos, opts = { end_col = prefix_end, conceal = "", hl_group = "BibCitePrefix" } }
		local key_start, key_end = line:find(patterns.citekey_rest, prefix_end + 1)
		if key_start and key_start == prefix_end + 1 then marks[#marks + 1] = { col = key_start - 1, opts = { end_col = key_end, hl_group = "BibCiteKey" } } end
		return marks
	end)
end

return conceal
