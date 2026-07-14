local test = require("mini.test")
local tu = dofile("tests/utils.lua")
local eq = test.expect.equality

local child, T = tu.new_child_set()

T["zotero_backend"] = test.new_set()

T["zotero_backend"]["load"] = function()
	local dir = tu.temp_dir()
	tu.setup_zotero_db(child, dir)
	-- Write a markdown file that triggers Zotero via config
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, md, "# Hello\nSee @smith2020.")
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua(string.format("require('bib.config').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir, "zotero.sqlite")))
	eq(child.lua_get("require('bib.backends.zotero').load()"), true)
end

T["zotero_backend"]["match by citekey prefix"] = function()
	local dir = tu.temp_dir()
	tu.setup_zotero_db(child, dir)
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, md, "# Hello")
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua(string.format("require('bib.config').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir, "zotero.sqlite")))
	child.lua("require('bib.backends.zotero').load()")
	eq(child.lua_get("#require('bib.backends.zotero').match('smi')"), 1)
	eq(child.lua_get("require('bib.backends.zotero').match('smi')[1].key"), "ABC123#smith2020")
end

T["zotero_backend"]["get by key"] = function()
	local dir = tu.temp_dir()
	tu.setup_zotero_db(child, dir)
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, md, "# Hello")
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua(string.format("require('bib.config').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir, "zotero.sqlite")))
	child.lua("require('bib.backends.zotero').load()")
	eq(child.lua_get("require('bib.backends.zotero').get('ABC123#smith2020').type"), "journalArticle")
	eq(child.lua_get("require('bib.backends.zotero').get('ABC123#smith2020').fields.author"), "John Smith")
end

T["zotero_backend"]["definition returns zotero URI"] = function()
	local dir = tu.temp_dir()
	tu.setup_zotero_db(child, dir)
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, md, "# Hello")
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua(string.format("require('bib.config').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir, "zotero.sqlite")))
	child.lua("require('bib.backends.zotero').load()")
	eq(child.lua_get("require('bib.backends.zotero').definition('ABC123#smith2020').uri"), "zotero://select/library/items/ABC123")
end

T["zotero_backend"]["hover contains author and title"] = function()
	local dir = tu.temp_dir()
	tu.setup_zotero_db(child, dir)
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, md, "# Hello")
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua(string.format("require('bib.config').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir, "zotero.sqlite")))
	child.lua("require('bib.backends.zotero').load()")
	local hover = child.lua_get("require('bib.backends.zotero').hover('ABC123#smith2020')")
	eq(hover:find("John Smith") ~= nil, true)
	eq(hover:find("Test Title") ~= nil, true)
end

return T
