local test = require("mini.test")
local u = dofile("tests/utils.lua")
local eq = test.expect.equality

local child, T = u.new_child_set()

T["conceal"] = test.new_set()

local function setup_conceal(content)
	local dir = u.temp_dir()
	local md = vim.fs.joinpath(dir, "paper.md")
	u.write_file(child, md, content)
	child.lua(string.format("vim.cmd.edit(%q)", md))
	local bufnr = child.lua_get("vim.api.nvim_get_current_buf()")
	child.lua(string.format("require('bib.conceal').setup(%d)", bufnr))
	child.lua(string.format("vim.api.nvim_exec_autocmds('BufWinEnter', { buffer = %d })", bufnr))
	return child.lua([[
    local ns = vim.api.nvim_get_namespaces()["bib_conceal"]
    local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
    table.sort(marks, function(a, b) return a[3] < b[3] end)
    return marks
  ]])
end

T["conceal"]["extmarks placed at correct 0-indexed columns"] = function()
	local extmarks = setup_conceal("see @ABC123#smith2020 for details")

	eq(#extmarks, 3)

	-- Extmark 1: @ at 0-indexed col 4 (end_col=5 is default, not in details)
	eq(extmarks[1][3], 4)
	eq(extmarks[1][4].hl_group, "BibCitePrefix")

	-- Extmark 2: ABC123# at 0-indexed col 5-12, concealed
	eq(extmarks[2][3], 5)
	eq(extmarks[2][4].end_col, 12)
	eq(extmarks[2][4].conceal, "")

	-- Extmark 3: smith2020 at 0-indexed col 12-21, BibCiteKey
	eq(extmarks[3][3], 12)
	eq(extmarks[3][4].end_col, 21)
	eq(extmarks[3][4].hl_group, "BibCiteKey")
end

T["conceal"]["skips citekey extmark when no citekey follows prefix"] = function()
	local extmarks = setup_conceal("see @ABC123# and more text")

	-- Only 2 extmarks: @ and ITEMID#, no citekey
	eq(#extmarks, 2)

	eq(extmarks[1][3], 4)
	eq(extmarks[1][4].hl_group, "BibCitePrefix")

	eq(extmarks[2][3], 5)
	eq(extmarks[2][4].end_col, 12)
	eq(extmarks[2][4].conceal, "")
end

T["conceal"]["handles multiple prefixes on one line"] = function()
	local extmarks = setup_conceal("see @ABC123#smith2020 and @DEF456#jones2021")

	-- 6 extmarks: 3 per prefix
	eq(#extmarks, 6)

	-- First prefix: @ at 4, ABC123# at 5-12, smith2020 at 12-21
	eq(extmarks[1][3], 4)
	eq(extmarks[2][3], 5)
	eq(extmarks[2][4].end_col, 12)
	eq(extmarks[2][4].conceal, "")
	eq(extmarks[3][3], 12)
	eq(extmarks[3][4].end_col, 21)

	-- Second prefix: @ at 26, DEF456# at 27-34, jones2021 at 34-43
	eq(extmarks[4][3], 26)
	eq(extmarks[5][3], 27)
	eq(extmarks[5][4].end_col, 34)
	eq(extmarks[5][4].conceal, "")
	eq(extmarks[6][3], 34)
	eq(extmarks[6][4].end_col, 43)
end

T["conceal"]["extmarks update after text changed"] = function()
	local dir = u.temp_dir()
	local md = vim.fs.joinpath(dir, "paper.md")
	u.write_file(child, md, "see @ABC123#smith2020 for details")
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua("require('bib.conceal').setup(vim.api.nvim_get_current_buf())")
	child.lua("vim.api.nvim_exec_autocmds('BufWinEnter', { buffer = 0 })")

	-- Replace the line with new citekey
	child.lua("vim.api.nvim_buf_set_lines(0, 0, 1, false, {'see @ABC123#jones2021 for details'})")
	child.lua("vim.api.nvim_exec_autocmds('TextChanged', { buffer = 0 })")

	local extmarks = child.lua([[
		local ns = vim.api.nvim_get_namespaces()["bib_conceal"]
		local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
		table.sort(marks, function(a, b) return a[3] < b[3] end)
		return marks
	]])

	eq(#extmarks, 3)

	-- Prefix extmarks unchanged
	eq(extmarks[1][3], 4) -- @
	eq(extmarks[2][3], 5) -- ABC123# (concealed)
	eq(extmarks[2][4].conceal, "")

	-- Citekey extmark now covers "jones2021" at cols 12-21
	eq(extmarks[3][3], 12)
	eq(extmarks[3][4].end_col, 21)
	eq(extmarks[3][4].hl_group, "BibCiteKey")
end

T["conceal"]["extmarks persist after BufWritePost"] = function()
	local extmarks = setup_conceal("see @ABC123#smith2020 for details")

	-- Trigger BufWritePost — content unchanged
	child.lua("vim.api.nvim_exec_autocmds('BufWritePost', { buffer = 0 })")

	local marks = child.lua([[
		local ns = vim.api.nvim_get_namespaces()["bib_conceal"]
		local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
		table.sort(marks, function(a, b) return a[3] < b[3] end)
		return marks
	]])

	eq(#marks, 3)
	eq(marks[3][4].hl_group, "BibCiteKey")
end

return T
