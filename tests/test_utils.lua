local test = require("mini.test")
local u = dofile("tests/utils.lua")
local eq = test.expect.equality

local child, T = u.new_child_set()

T["yaml_field"] = test.new_set()

vim
	.iter({
		{ name = "extracts string bibliography field", content = "---\ntitle: My Paper\nbibliography: refs.bib\n---\n\n# Hello\n", expected = "refs.bib" },
		{ name = "returns nil when no yaml header", content = "# Hello\n", expected = vim.NIL },
		{ name = "returns nil when field missing", content = "---\ntitle: My Paper\n---\n\n# Hello\n", expected = vim.NIL },
	})
	:each(function(c)
		T["yaml_field"][c.name] = function()
			local dir = u.temp_dir()
			local md = vim.fs.joinpath(dir, "paper.md")
			u.write_file(child, md, c.content)
			child.lua(string.format("vim.cmd.edit(%q)", md))
			eq(child.lua_get("require('bib.yaml').field('bibliography', vim.api.nvim_get_current_buf())"), c.expected)
		end
	end)

T["key_at"] = test.new_set()

vim
	.iter({
		{ name = "extracts key from @citation", content = "see @smith2020 for details\n", col = 6, expected = "smith2020" },
		{ name = "handles keys with hyphens", content = "see @smith-jones-2020 for details\n", col = 6, expected = "smith-jones-2020" },
		{ name = "extracts composite key", content = "see @ABC123#smith2020 for details\n", col = 6, expected = "ABC123#smith2020" },
	})
	:each(function(c)
		T["key_at"][c.name] = function()
			local dir = u.temp_dir()
			local md = vim.fs.joinpath(dir, "paper.md")
			u.write_file(child, md, c.content)
			child.lua(string.format("vim.cmd.edit(%q)", md))
			eq(child.lua_get(string.format("require('bib.utils.lsp').citekey_at(vim.api.nvim_get_current_buf(), 0, %d)", c.col)), c.expected)
		end
	end)

T["partial_key"] = test.new_set()

vim
	.iter({
		{ name = "extracts partial markdown key", content = "see @smit\n", col = 8, expected = "smi" },
		{ name = "extracts partial composite key", content = "see @ABC#smit\n", col = 12, expected = "ABC#smi" },
		{ name = "returns nil when no partial key", content = "just text\n", col = 5, expected = vim.NIL },
	})
	:each(function(c)
		T["partial_key"][c.name] = function()
			local dir = u.temp_dir()
			local ext = c.ft or "md"
			local fpath = vim.fs.joinpath(dir, "paper." .. ext)
			u.write_file(child, fpath, c.content)
			child.lua(string.format("vim.cmd.edit(%q)", fpath))
			eq(child.lua_get(string.format("require('bib.utils.lsp').citekey_at(vim.api.nvim_get_current_buf(), 0, %d, true)", c.col)), c.expected)
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
			child.lua(string.format("_G._r = require('bib.utils.backends').resolve_path(%q, %q)", c.base, c.path))
			eq(child.lua_get("_G._r"), c.expected)
		end
	end)

T["format"] = test.new_set()

T["format"]["format_item returns author - title"] = function()
	child.lua("_G._e = { fields = { author = 'John Smith', title = 'Test Paper' }, citekey = 'smith2020' }")
	eq(child.lua_get("require('bib.utils').format_item(_G._e)"), "Smith - Test Paper")
end

T["format"]["format_item returns author (year) - title"] = function()
	child.lua("_G._e = { fields = { author = 'John Smith', title = 'Test', year = '2020' }, citekey = 'smith2020' }")
	eq(child.lua_get("require('bib.utils').format_item(_G._e)"), "Smith (2020) - Test")
end

T["format"]["format_item uses et al for 3+ authors"] = function()
	child.lua("_G._e = { fields = { author = 'A, B, C', title = 'Test' }, citekey = 'x' }")
	eq(child.lua_get("require('bib.utils').format_item(_G._e)"), "A et al - Test")
end

T["format"]["format_item prefers creators.author over fields.author"] = function()
	child.lua("_G._e = { creators = { author = 'Smith, John' }, fields = { author = 'Old Name', title = 'Test' }, citekey = 'x' }")
	eq(child.lua_get("require('bib.utils').format_item(_G._e)"), "Smith, John - Test")
end

T["format"]["display_key prefers citekey over key"] = function()
	child.lua("_G._e = { citekey = 'smith2020', key = 'ABC#smith2020' }")
	eq(child.lua_get("require('bib.utils').display_key(_G._e)"), "smith2020")
end

T["format"]["display_key falls back to key"] = function()
	child.lua("_G._e = { key = 'smith2020' }")
	eq(child.lua_get("require('bib.utils').display_key(_G._e)"), "smith2020")
end

T["ts"] = test.new_set()

T["ts"]["capture_ids builds name->id map"] = function()
	local ids = require("bib.ts").capture_ids({ captures = { [3] = "author", [7] = "title" } })
	eq(ids.author, 3)
	eq(ids.title, 7)
end

T["selection"] = test.new_set()

T["selection"]["handle_selection opens zotero URI for zotkey"] = function()
	child.lua([[
		_G._opened = nil
		vim.ui.open = function(uri) _G._opened = uri end
		require('bib.utils').handle_selection({ zotkey = 'ABC123' })
	]])
	eq(child.lua_get("_G._opened"), "zotero://select/library/items/ABC123")
end

T["selection"]["handle_selection returns early for nil item"] = function()
	child.lua([[
		_G._opened = nil
		vim.ui.open = function(uri) _G._opened = uri end
		require('bib.utils').handle_selection(nil)
	]])
	eq(child.lua_get("_G._opened"), vim.NIL)
end

return T
