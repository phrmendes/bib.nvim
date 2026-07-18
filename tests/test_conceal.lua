local test = require("mini.test")
local tu = dofile("tests/utils.lua")
local eq = test.expect.equality

local child, T = tu.new_child_set()

T["conceal"] = test.new_set()

local function setup_conceal(content)
	local dir = tu.temp_dir()
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, md, content)
	child.lua(string.format("vim.cmd.edit(%q)", md))
	local bufnr = child.lua_get("vim.api.nvim_get_current_buf()")
	child.lua(string.format("require('bib.conceal').setup(%d)", bufnr))
	child.lua(string.format("vim.api.nvim_exec_autocmds('BufWinEnter', { buffer = %d })", bufnr))
	return child.lua([[
    local ns = vim.api.nvim_get_namespaces()["bib_conceal"]
    local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
    table.sort(marks, function(a, b) return a[2] < b[2] end)
    return marks
  ]])
end

T["conceal"]["extmarks placed at correct 0-indexed columns"] = function()
	local extmarks = setup_conceal("see @ABC123#smith2020 for details")

	eq(#extmarks, 3)

	-- Extmark 1: @ at 0-indexed col 4-5, BibCitePrefix, no conceal
	eq(extmarks[1][2], 4)
	eq(extmarks[1][3], 5)
	eq(extmarks[1][4].hl_group, "BibCitePrefix")
	eq(extmarks[1][4].conceal, vim.NIL)

	-- Extmark 2: ABC123# at 0-indexed col 5-12, concealed
	eq(extmarks[2][2], 5)
	eq(extmarks[2][3], 12)
	eq(extmarks[2][4].conceal, "")

	-- Extmark 3: smith2020 at 0-indexed col 12-21, BibCiteKey, no conceal
	eq(extmarks[3][2], 12)
	eq(extmarks[3][3], 21)
	eq(extmarks[3][4].hl_group, "BibCiteKey")
	eq(extmarks[3][4].conceal, vim.NIL)
end

T["conceal"]["skips citekey extmark when no citekey follows prefix"] = function()
	local extmarks = setup_conceal("see @ABC123# and more text")

	-- Only 2 extmarks: @ and ITEMID#, no citekey
	eq(#extmarks, 2)

	eq(extmarks[1][2], 4)
	eq(extmarks[1][3], 5)
	eq(extmarks[1][4].hl_group, "BibCitePrefix")

	eq(extmarks[2][2], 5)
	eq(extmarks[2][3], 12)
	eq(extmarks[2][4].conceal, "")
end

T["conceal"]["handles multiple prefixes on one line"] = function()
	local extmarks = setup_conceal("see @ABC123#smith2020 and @DEF456#jones2021")

	-- 6 extmarks: 3 per prefix
	eq(#extmarks, 6)

	-- First prefix: @ at 4-5, ABC123# at 5-12, smith2020 at 12-21
	eq(extmarks[1][2], 4)
	eq(extmarks[1][3], 5)
	eq(extmarks[2][2], 5)
	eq(extmarks[2][3], 12)
	eq(extmarks[2][4].conceal, "")
	eq(extmarks[3][2], 12)
	eq(extmarks[3][3], 21)

	-- Second prefix: @ at 26-27, DEF456# at 27-34, jones2021 at 34-43
	eq(extmarks[4][2], 26)
	eq(extmarks[4][3], 27)
	eq(extmarks[5][2], 27)
	eq(extmarks[5][3], 34)
	eq(extmarks[5][4].conceal, "")
	eq(extmarks[6][2], 34)
	eq(extmarks[6][3], 43)
end

return T
