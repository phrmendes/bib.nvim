local test = require("mini.test")
local tu = dofile("tests/utils.lua")
local eq = test.expect.equality

local child, T = tu.new_child_set()

T["yaml_field"] = test.new_set()

vim
	.iter({
		{ name = "extracts string bibliography field", content = "---\ntitle: My Paper\nbibliography: refs.bib\n---\n\n# Hello\n", expected = "refs.bib" },
		{ name = "returns nil when no yaml header", content = "# Hello\n", expected = vim.NIL },
		{ name = "returns nil when field missing", content = "---\ntitle: My Paper\n---\n\n# Hello\n", expected = vim.NIL },
	})
	:each(function(c)
		T["yaml_field"][c.name] = function()
			local dir = tu.temp_dir()
			local md = vim.fs.joinpath(dir, "paper.md")
			tu.write_file(child, md, c.content)
			child.lua(string.format("vim.cmd.edit(%q)", md))
			eq(child.lua_get("require('bib.yaml').field('bibliography', vim.api.nvim_get_current_buf())"), c.expected)
		end
	end)

T["key_at"] = test.new_set()

vim
	.iter({
		{ name = "extracts key from @citation", content = "see @smith2020 for details\n", col = 6, expected = "smith2020" },
		{ name = "handles keys with hyphens", content = "see @smith-jones-2020 for details\n", col = 6, expected = "smith-jones-2020" },
	})
	:each(function(c)
		T["key_at"][c.name] = function()
			local dir = tu.temp_dir()
			local md = vim.fs.joinpath(dir, "paper.md")
			tu.write_file(child, md, c.content)
			child.lua(string.format("vim.cmd.edit(%q)", md))
			eq(child.lua_get(string.format("require('bib.utils').key_at(vim.api.nvim_get_current_buf(), 0, %d)", c.col)), c.expected)
		end
	end)

T["partial_key"] = test.new_set()

vim
	.iter({
		{ name = "extracts partial markdown key", content = "see @smit\n", col = 8, expected = "smi" },
		{ name = "returns nil when no partial key", content = "just text\n", col = 5, expected = vim.NIL },
	})
	:each(function(c)
		T["partial_key"][c.name] = function()
			local dir = tu.temp_dir()
			local ext = c.ft or "md"
			local fpath = vim.fs.joinpath(dir, "paper." .. ext)
			tu.write_file(child, fpath, c.content)
			child.lua(string.format("vim.cmd.edit(%q)", fpath))
			eq(child.lua_get(string.format("require('bib.utils').key_at(vim.api.nvim_get_current_buf(), 0, %d, true)", c.col)), c.expected)
		end
	end)

T["resolve_path"] = test.new_set()

vim
	.iter({
		{ name = "resolves relative path", base = "/home/user/docs", path = "refs.bib", expected = "/home/user/docs/refs.bib" },
		{ name = "passes through absolute path", base = "/home", path = "/etc/refs.bib", expected = "/etc/refs.bib" },
	})
	:each(function(c)
		T["resolve_path"][c.name] = function()
			child.lua(string.format("_G._r = require('bib.utils').resolve_path(%q, %q)", c.base, c.path))
			eq(child.lua_get("_G._r"), c.expected)
		end
	end)

return T
