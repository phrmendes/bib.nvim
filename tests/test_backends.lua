local test = require("mini.test")
local tu = dofile("tests/utils.lua")
local eq = test.expect.equality

local child, T = tu.new_child_set()

local entry = "@article{smith2020,\n  author = {John Smith},\n  title = {Test},\n  year = {2020}\n}"
local entry2 = "@book{jones2021,\n  author = {Jane Jones},\n  title = {Book},\n  year = {2021}\n}"
local both = entry .. "\n" .. entry2

T["load"] = test.new_set()

vim
	.iter({
		{ name = "returns true when bib found", has_bib = true, expected = true },
		{ name = "returns false when no bib", has_bib = false, expected = false },
	})
	:each(function(c)
		T["load"][c.name] = function()
			local dir = tu.temp_dir()
			local md = vim.fs.joinpath(dir, "paper.md")
			if c.has_bib then tu.write_file(child, vim.fs.joinpath(dir, "refs.bib"), entry) end
			tu.write_file(child, md, c.has_bib and "---\nbibliography: refs.bib\n---\n" or "# No bib")
			child.lua(string.format("vim.cmd.edit(%q)", md))
			eq(child.lua_get(string.format("pcall(require('bib.backends.bib').load, %d)", vim.api.nvim_get_current_buf())), c.expected)
		end
	end)

T["match"] = test.new_set()

T["match"]["matches by prefix"] = function()
	tu.setup_bib(child, both)
	eq(child.lua_get("#require('bib.backends.bib').match('smi')"), 1)
	eq(child.lua_get("require('bib.backends.bib').match('smi')[1].key"), "smith2020")
end

T["get"] = test.new_set()

vim
	.iter({
		{ field = "key", expected = "smith2020" },
		{ field = "type", expected = "article" },
		{ field = "fields.author", expected = "John Smith" },
	})
	:each(function(c)
		T["get"]["returns " .. c.field] = function()
			tu.setup_bib(child, entry)
			eq(child.lua_get("require('bib.backends.bib').get('smith2020')." .. c.field), c.expected)
		end
	end)

T["definition"] = test.new_set()

T["definition"]["returns location with uri"] = function()
	local dir = tu.setup_bib(child, entry)
	eq(child.lua_get("require('bib.backends.bib').definition('smith2020').uri"), vim.uri_from_fname(vim.fs.joinpath(dir, "refs.bib")))
end

T["hover"] = test.new_set()

T["hover"]["format is author - title - year"] = function()
	tu.setup_bib(child, entry)
	eq(child.lua_get("require('bib.backends.bib').hover('smith2020')"), "# John Smith - Test - 2020")
end

T["hover"]["contains author"] = function()
	tu.setup_bib(child, entry)
	eq(child.lua_get("require('bib.backends.bib').hover('smith2020'):find('John Smith') ~= nil"), true)
end

T["hover"]["includes abstract when present"] = function()
	local with_abstract = "@article{test2020,\n  author = {Jane Doe},\n  title = {With Abstract},\n  year = {2020},\n  abstract = {A test  abstract.}\n}"
	tu.setup_bib(child, with_abstract)
	local hover = child.lua_get("require('bib.backends.bib').hover('test2020')")
	eq(hover:find("---") ~= nil, true)
	eq(hover:find("A test abstract.") ~= nil, true)
end

T["definition"]["returns correct 0-indexed line range"] = function()
	tu.setup_bib(child, entry)
	eq(child.lua_get("require('bib.backends.bib').definition('smith2020').range.start.line"), 0)
	eq(child.lua_get("require('bib.backends.bib').definition('smith2020').range.start.character"), 0)
end

return T
