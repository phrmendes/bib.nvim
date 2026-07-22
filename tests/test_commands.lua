local test = require("mini.test")
local tu = dofile("tests/utils.lua")
local eq = test.expect.equality

local child, T = tu.new_child_set()

local entry = "@article{smith2020,\n  author = {John Smith},\n  title = {Test},\n  year = {2020}\n}"
local both = entry .. "\n" .. "@book{jones2021,\n  author = {Jane Jones},\n  title = {Book},\n  year = {2021}\n}"

T["search"] = test.new_set()

T["search"]["shows bib entries in picker"] = function()
	local dir = tu.temp_dir()
	tu.write_file(child, vim.fs.joinpath(dir, "refs.bib"), both)
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, md, "---\nbibliography: refs.bib\n---\n")
	child.lua(string.format("vim.cmd.edit(%q)", md))

	child.lua([[
		_G._sel_items = nil
		vim.ui.select = function(items, opts, on_choice)
			_G._sel_items = items
		end
	]])

	child.lua("require('bib.commands').search('')")
	child.lua("vim.wait(1000, function() return _G._sel_items ~= nil end)")

	local items = child.lua_get("_G._sel_items")
	eq(#items, 2)

	local keys = vim.iter(items):map(function(i) return i.display:match("^[^-]+ %- ([^ ]+) ") end):totable()
	eq(vim.iter(keys):find(function(k) return k == "smith2020" end) ~= nil, true)
	eq(vim.iter(keys):find(function(k) return k == "jones2021" end) ~= nil, true)

	local titles = vim.iter(items):map(function(i) return i.display:match(" %- ([^ ]+)$") end):totable()
	eq(vim.iter(titles):find(function(t) return t == "Test" end) ~= nil, true)
	eq(vim.iter(titles):find(function(t) return t == "Book" end) ~= nil, true)
end

T["search"]["shows zotero entries in picker"] = function()
	local dir = tu.temp_dir()
	tu.setup_zotero_db(child, dir)
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, md, "# Hello")
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua(string.format("require('bib').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir, "zotero.sqlite")))

	child.lua([[
		_G._sel_items = nil
		vim.ui.select = function(items, opts, on_choice)
			_G._sel_items = items
		end
	]])

	child.lua("require('bib.commands').search('zotero')")
	child.lua("vim.wait(1000, function() return _G._sel_items ~= nil end)")

	local items = child.lua_get("_G._sel_items")
	eq(#items, 1)

	local _, id, t = items[1].display:match("^(.+) %- (.+) %- (.+)$")
	eq(id, "smith2020")
	eq(t, "Test Title")
end

T["search"]["format is author - id - title"] = function()
	local dir = tu.temp_dir()
	tu.write_file(child, vim.fs.joinpath(dir, "refs.bib"), entry)
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, md, "---\nbibliography: refs.bib\n---\n")
	child.lua(string.format("vim.cmd.edit(%q)", md))

	child.lua([[
		_G._sel_items = nil
		vim.ui.select = function(items, opts, on_choice)
			_G._sel_items = items
		end
	]])

	child.lua("require('bib.commands').search('')")
	child.lua("vim.wait(1000, function() return _G._sel_items ~= nil end)")

	local items = child.lua_get("_G._sel_items")
	local author, id, title = items[1].display:match("^(.+) %- (.+) %- (.+)$")
	eq(author, "Smith")
	eq(id, "smith2020")
	eq(title, "Test")
end

T["search"]["selection opens zotero URI"] = function()
	local dir = tu.temp_dir()
	tu.setup_zotero_db(child, dir)
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, md, "# Hello")
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua(string.format("require('bib').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir, "zotero.sqlite")))

	child.lua([[
		_G._opened = nil
		vim.ui.open = function(uri) _G._opened = uri end
		vim.ui.select = function(items, opts, on_choice)
			on_choice(items[1])
		end
	]])

	child.lua("require('bib.commands').search('zotero')")
	child.lua("vim.wait(1000, function() return _G._opened ~= nil end)")

	local uri = child.lua_get("_G._opened")
	eq(uri, "zotero://select/library/items/ABC123")
end

T["search"]["selection jumps to bib file"] = function()
	local dir = tu.temp_dir()
	tu.write_file(child, vim.fs.joinpath(dir, "refs.bib"), entry)
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, md, "---\nbibliography: refs.bib\n---\n")
	child.lua(string.format("vim.cmd.edit(%q)", md))

	child.lua([[
		_G._loc = nil
		vim.lsp.util.show_document = function(params, enc, opts) _G._loc = { uri = params.uri, range = params.selection } end
		vim.ui.select = function(items, opts, on_choice)
			on_choice(items[1])
		end
	]])

	child.lua("require('bib.commands').search('')")
	child.lua("vim.wait(1000, function() return _G._loc ~= nil end)")

	local loc = child.lua_get("_G._loc")
	eq(loc.uri, vim.uri_from_fname(vim.fs.joinpath(dir, "refs.bib")))
	eq(loc.range.start.line, 0)
end

return T
