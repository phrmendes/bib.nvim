local test = require("mini.test")
local tu = dofile("tests/utils.lua")
local eq = test.expect.equality

local child, T = tu.new_child_set()

local entry = "@article{smith2020,\n  author = {John Smith},\n  title = {Test},\n  year = {2020}\n}"

T["lsp_start"] = test.new_set()

vim
	.iter({
		{
			name = "attaches lsp client for bib buffer",
			content = entry,
			expected = true,
		},
		{
			name = "does not attach when no bib",
			content = nil,
			expected = false,
		},
	})
	:each(function(c)
		T["lsp_start"][c.name] = function()
			local dir = tu.temp_dir()
			local md = vim.fs.joinpath(dir, "paper.md")
			if c.content then tu.write_file(child, vim.fs.joinpath(dir, "refs.bib"), c.content) end
			tu.write_file(child, md, c.content and "---\nbibliography: refs.bib\n---\nSee @smith2020." or "# No bib")
			child.lua(string.format("vim.cmd.edit(%q)", md))
			child.lua("require('bib.lsp').start(vim.api.nvim_get_current_buf())")
			child.lua("vim.wait(500, function() return false end)")
			child.lua([[_G._bib_check = function() for _, c in ipairs(vim.lsp.get_clients({bufnr=0})) do if c.name == 'bib_ls' then return true end end; return false end]])
			eq(child.lua_get("_G._bib_check()"), c.expected)
		end
	end)

return T
