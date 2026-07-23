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

local function col(marks, i) return marks[i][3] end
local function end_col(marks, i) return marks[i][4].end_col end
local function hl(marks, i) return marks[i][4].hl_group end
local function conceal(marks, i) return marks[i][4].conceal end

T["conceal"]["extmarks placed at correct 0-indexed columns"] = function()
	local extmarks = setup_conceal("see @ABC123#smith2020 for details")

	eq(#extmarks, 3)
	eq(col(extmarks, 1), 4)
	eq(hl(extmarks, 1), "BibCitePrefix")
	eq(col(extmarks, 2), 5)
	eq(end_col(extmarks, 2), 12)
	eq(conceal(extmarks, 2), "")
	eq(col(extmarks, 3), 12)
	eq(end_col(extmarks, 3), 21)
	eq(hl(extmarks, 3), "BibCiteKey")
end

T["conceal"]["skips citekey extmark when no citekey follows prefix"] = function()
	local extmarks = setup_conceal("see @ABC123# and more text")

	eq(#extmarks, 2)
	eq(col(extmarks, 1), 4)
	eq(hl(extmarks, 1), "BibCitePrefix")
	eq(col(extmarks, 2), 5)
	eq(end_col(extmarks, 2), 12)
	eq(conceal(extmarks, 2), "")
end

T["conceal"]["handles multiple prefixes on one line"] = function()
	local extmarks = setup_conceal("see @ABC123#smith2020 and @DEF456#jones2021")

	eq(#extmarks, 6)

	local at1, prefix1_end, citekey1_start, citekey1_end = 4, 12, 12, 21
	eq(col(extmarks, 1), at1)
	eq(col(extmarks, 2), at1 + 1)
	eq(end_col(extmarks, 2), prefix1_end)
	eq(conceal(extmarks, 2), "")
	eq(col(extmarks, 3), citekey1_start)
	eq(end_col(extmarks, 3), citekey1_end)

	local at2, prefix2_end, citekey2_start, citekey2_end = 26, 34, 34, 43
	eq(col(extmarks, 4), at2)
	eq(col(extmarks, 5), at2 + 1)
	eq(end_col(extmarks, 5), prefix2_end)
	eq(conceal(extmarks, 5), "")
	eq(col(extmarks, 6), citekey2_start)
	eq(end_col(extmarks, 6), citekey2_end)
end

T["conceal"]["extmarks update after text changed"] = function()
	local dir = u.temp_dir()
	local md = vim.fs.joinpath(dir, "paper.md")
	u.write_file(child, md, "see @ABC123#smith2020 for details")
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua("require('bib.conceal').setup(vim.api.nvim_get_current_buf())")
	child.lua("vim.api.nvim_exec_autocmds('BufWinEnter', { buffer = 0 })")

	child.lua("vim.api.nvim_buf_set_lines(0, 0, 1, false, {'see @ABC123#jones2021 for details'})")
	child.lua("vim.api.nvim_exec_autocmds('TextChanged', { buffer = 0 })")

	local extmarks = child.lua([[
		local ns = vim.api.nvim_get_namespaces()["bib_conceal"]
		local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
		table.sort(marks, function(a, b) return a[3] < b[3] end)
		return marks
	]])

	eq(#extmarks, 3)
	eq(col(extmarks, 1), 4)
	eq(col(extmarks, 2), 5)
	eq(conceal(extmarks, 2), "")
	eq(col(extmarks, 3), 12)
	eq(end_col(extmarks, 3), 21)
	eq(hl(extmarks, 3), "BibCiteKey")
end

T["conceal"]["extmarks persist after BufWritePost"] = function()
	local extmarks = setup_conceal("see @ABC123#smith2020 for details")

	child.lua("vim.api.nvim_exec_autocmds('BufWritePost', { buffer = 0 })")

	local marks = child.lua([[
		local ns = vim.api.nvim_get_namespaces()["bib_conceal"]
		local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
		table.sort(marks, function(a, b) return a[3] < b[3] end)
		return marks
	]])

	eq(#marks, 3)
	eq(hl(marks, 3), "BibCiteKey")
end

T["conceal"]["skips code fences"] = function()
	local extmarks = setup_conceal("```markdown\n@ABC123#smith2020\n```")
	eq(#extmarks, 0)
end

T["conceal"]["plain @citekey gets prefix and key marks"] = function()
	local extmarks = setup_conceal("see @smith2020 for details")

	eq(#extmarks, 2)
	eq(col(extmarks, 1), 4)
	eq(hl(extmarks, 1), "BibCitePrefix")
	eq(col(extmarks, 2), 5)
	eq(end_col(extmarks, 2), 14)
	eq(hl(extmarks, 2), "BibCiteKey")
end

return T
