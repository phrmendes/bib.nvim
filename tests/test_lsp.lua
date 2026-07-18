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
			child.lua("require('bib.config').setup({ zotero = { database = '/tmp/nonexistent.sqlite' } })")
			child.lua("require('bib.lsp').start(vim.api.nvim_get_current_buf())")
			child.lua("vim.wait(500, function() return false end)")
			child.lua([[_G._bib_check = function() for _, c in ipairs(vim.lsp.get_clients({bufnr=0})) do if c.name == 'bib_ls' then return true end end; return false end]])
			eq(child.lua_get("_G._bib_check()"), c.expected)
		end
	end)

T["lsp_handlers"] = test.new_set()

T["lsp_handlers"]["completion returns items matching prefix"] = function()
	local dir = tu.temp_dir()
	tu.write_file(child, vim.fs.joinpath(dir, "refs.bib"), entry)
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, md, "---\nbibliography: refs.bib\n---\n\nSee @smi")
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua("require('bib.config').setup({ zotero = { database = '/tmp/nonexistent.sqlite' } })")
	child.lua("require('bib.lsp').pick(vim.api.nvim_get_current_buf())")
	child.lua([[
		_G._result = nil
		local server = require("bib.lsp").server()
		server.request("textDocument/completion", {
			textDocument = { uri = vim.uri_from_bufnr(0) },
			position = { line = 3, character = 7 },
		}, function(err, result)
			_G._result = { err = err, result = result }
		end)
	]])
	child.lua("vim.wait(1000, function() return _G._result ~= nil end)")
	local r = child.lua_get("_G._result")
	eq(r.err, vim.NIL)
	eq(#r.result.items, 1)
	eq(r.result.items[1].textEdit.newText, "smith2020")
	eq(r.result.items[1].kind, 21) -- Reference
end

T["lsp_handlers"]["completion returns empty when no key"] = function()
	local dir = tu.temp_dir()
	tu.write_file(child, vim.fs.joinpath(dir, "refs.bib"), entry)
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, md, "---\nbibliography: refs.bib\n---\n\nSee no key here")
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua("require('bib.config').setup({ zotero = { database = '/tmp/nonexistent.sqlite' } })")
	child.lua("require('bib.lsp').pick(vim.api.nvim_get_current_buf())")
	child.lua([[
		_G._result = nil
		local server = require("bib.lsp").server()
		server.request("textDocument/completion", {
			textDocument = { uri = vim.uri_from_bufnr(0) },
			position = { line = 3, character = 10 },
		}, function(err, result)
			_G._result = { err = err, result = result }
		end)
	]])
	child.lua("vim.wait(1000, function() return _G._result ~= nil end)")
	local r = child.lua_get("_G._result")
	eq(r.err, vim.NIL)
	eq(#r.result.items, 0)
end

T["lsp_handlers"]["definition returns bib file location"] = function()
	local dir = tu.temp_dir()
	tu.write_file(child, vim.fs.joinpath(dir, "refs.bib"), entry)
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, md, "---\nbibliography: refs.bib\n---\n\nSee @smith2020")
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua("require('bib.config').setup({ zotero = { database = '/tmp/nonexistent.sqlite' } })")
	child.lua("require('bib.lsp').pick(vim.api.nvim_get_current_buf())")
	child.lua([[
		_G._result = nil
		local server = require("bib.lsp").server()
		server.request("textDocument/definition", {
			textDocument = { uri = vim.uri_from_bufnr(0) },
			position = { line = 3, character = 12 },
		}, function(err, result)
			_G._result = { err = err, result = result }
		end)
	]])
	local r = child.lua_get("_G._result")
	eq(r.err, vim.NIL)
	eq(r.result.uri, vim.uri_from_fname(vim.fs.joinpath(dir, "refs.bib")))
	eq(r.result.range.start.line, 0)
end

T["lsp_handlers"]["hover returns formatted content"] = function()
	local dir = tu.temp_dir()
	tu.write_file(child, vim.fs.joinpath(dir, "refs.bib"), entry)
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, md, "---\nbibliography: refs.bib\n---\n\nSee @smith2020")
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua("require('bib.config').setup({ zotero = { database = '/tmp/nonexistent.sqlite' } })")
	child.lua("require('bib.lsp').pick(vim.api.nvim_get_current_buf())")
	child.lua([[
		_G._result = nil
		local server = require("bib.lsp").server()
		server.request("textDocument/hover", {
			textDocument = { uri = vim.uri_from_bufnr(0) },
			position = { line = 3, character = 12 },
		}, function(err, result)
			_G._result = { err = err, result = result }
		end)
	]])
	local r = child.lua_get("_G._result")
	eq(r.err, vim.NIL)
	local value = r.result.contents.value
	eq(value:find("John Smith") ~= nil, true)
	eq(value:find("Test") ~= nil, true)
	eq(value:find("2020") ~= nil, true)
end

T["lsp_handlers"]["completion returns empty inside code fence"] = function()
	local dir = tu.temp_dir()
	tu.write_file(child, vim.fs.joinpath(dir, "refs.bib"), entry)
	local md = vim.fs.joinpath(dir, "paper.md")
	tu.write_file(child, md, "---\nbibliography: refs.bib\n---\n\n```markdown\n@smi\n```\n\nSee @smi")
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua("require('bib.config').setup({ zotero = { database = '/tmp/nonexistent.sqlite' } })")
	child.lua("require('bib.lsp').pick(vim.api.nvim_get_current_buf())")
	child.lua([[
		_G._result = nil
		local server = require("bib.lsp").server()
		server.request("textDocument/completion", {
			textDocument = { uri = vim.uri_from_bufnr(0) },
			position = { line = 4, character = 4 },
		}, function(err, result)
			_G._result = { err = err, result = result }
		end)
	]])
	child.lua("vim.wait(1000, function() return _G._result ~= nil end)")
	local r = child.lua_get("_G._result")
	eq(r.err, vim.NIL)
	eq(#r.result.items, 0)
end

return T
