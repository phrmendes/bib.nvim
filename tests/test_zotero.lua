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
	eq(child.lua_get("pcall(require('bib.backends.zotero').load)"), true)
end

T["zotero_backend"]["match by citekey prefix"] = function()
	local dir = tu.temp_dir()
	tu.setup_zotero_db(child, dir)
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, md, "# Hello")
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua(string.format("require('bib.config').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir, "zotero.sqlite")))
	child.lua("pcall(require('bib.backends.zotero').load)")
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
	child.lua("pcall(require('bib.backends.zotero').load)")
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
	child.lua("pcall(require('bib.backends.zotero').load)")
	eq(child.lua_get("require('bib.backends.zotero').definition('ABC123#smith2020').uri"), "zotero://select/library/items/ABC123")
end

T["zotero_backend"]["hover contains author and title"] = function()
	local dir = tu.temp_dir()
	tu.setup_zotero_db(child, dir)
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, md, "# Hello")
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua(string.format("require('bib.config').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir, "zotero.sqlite")))
	child.lua("pcall(require('bib.backends.zotero').load)")
	local hover = child.lua_get("require('bib.backends.zotero').hover('ABC123#smith2020')")
	eq(hover:find("John Smith") ~= nil, true)
	eq(hover:find("Test Title") ~= nil, true)
end

T["zotero_backend"]["completion label uses citekey not full key"] = function()
	local dir = tu.temp_dir()
	tu.setup_zotero_db(child, dir)
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, md, "# Hello")
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua(string.format("require('bib.config').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir, "zotero.sqlite")))
	child.lua("pcall(require('bib.backends.zotero').load)")
	local entry = child.lua_get("require('bib.backends.zotero').match('smi')[1]")
	eq(entry.key, "ABC123#smith2020")
	eq(entry.citekey, "smith2020")
end

T["zotero_backend"]["hover format is author - title - year"] = function()
	local dir = tu.temp_dir()
	tu.setup_zotero_db(child, dir)
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, md, "# Hello")
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua(string.format("require('bib.config').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir, "zotero.sqlite")))
	child.lua("pcall(require('bib.backends.zotero').load)")
	local hover = child.lua_get("require('bib.backends.zotero').hover('ABC123#smith2020')")
	eq(hover, "# John Smith - Test Title - 2020\n\n---\nAn abstract.")
end

T["zotero_backend"]["auto-dispatch uses bib when available"] = function()
	local dir = tu.temp_dir()
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, vim.fs.joinpath(dir, "refs.bib"), "@article{test, title = {Test}, year = {2020}}")
	tu.write_file(child, md, "---\nbibliography: refs.bib\n---\nSee @test.")
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua("require('bib.config').setup()")
	child.lua("_G._backend = require('bib.lsp').pick(vim.api.nvim_get_current_buf())")
	eq(child.lua_get("type(_G._backend)"), "table")
	eq(child.lua_get("_G._backend.get('test') ~= nil"), true)
end

T["zotero_failures"] = test.new_set()

T["zotero_failures"]["load fails when database not found"] = function()
	local dir = tu.temp_dir()
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, md, "# Hello")
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua(string.format("require('bib.config').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir, "zotero.sqlite")))
	eq(child.lua_get("pcall(require('bib.backends.zotero').load)"), false)
end

T["zotero_failures"]["load fails when database is empty"] = function()
	local dir = tu.temp_dir()
	tu.setup_zotero_db_empty(child, dir)
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, md, "# Hello")
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua(string.format("require('bib.config').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir, "zotero.sqlite")))
	local ok, err = child.lua_get("pcall(require('bib.backends.zotero').load)")
	eq(ok, false)
end

T["zotero_failures"]["load fails with malformed schema"] = function()
	local dir = tu.temp_dir()
	tu.setup_zotero_db_malformed(child, dir)
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, md, "# Hello")
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua(string.format("require('bib.config').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir, "zotero.sqlite")))
	eq(child.lua_get("pcall(require('bib.backends.zotero').load)"), false)
end

T["zotero_search"] = test.new_set()

T["zotero_search"]["matches by citekey substring"] = function()
	local dir = tu.temp_dir()
	tu.setup_zotero_db(child, dir)
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, md, "# Hello")
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua(string.format("require('bib.config').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir, "zotero.sqlite")))
	child.lua("pcall(require('bib.backends.zotero').load)")
	eq(child.lua_get("#require('bib.backends.zotero').search('smit')"), 1)
	eq(child.lua_get("require('bib.backends.zotero').search('smit')[1].citekey"), "smith2020")
end

T["zotero_search"]["matches by title substring"] = function()
	local dir = tu.temp_dir()
	tu.setup_zotero_db(child, dir)
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, md, "# Hello")
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua(string.format("require('bib.config').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir, "zotero.sqlite")))
	child.lua("pcall(require('bib.backends.zotero').load)")
	eq(child.lua_get("#require('bib.backends.zotero').search('Test')"), 1)
end

T["zotero_search"]["matches by author substring"] = function()
	local dir = tu.temp_dir()
	tu.setup_zotero_db(child, dir)
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, md, "# Hello")
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua(string.format("require('bib.config').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir, "zotero.sqlite")))
	child.lua("pcall(require('bib.backends.zotero').load)")
	eq(child.lua_get("#require('bib.backends.zotero').search('John')"), 1)
end

return T
