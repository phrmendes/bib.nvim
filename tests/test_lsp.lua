local test = require("mini.test")
local u = dofile("tests/utils.lua")
local eq = test.expect.equality

local child, T = u.new_child_set()

local entry = "@article{smith2020,\n  author = {John Smith},\n  title = {Test},\n  year = {2020}\n}"

T["lsp_start"] = test.new_set()

vim
	.iter({
		{ name = "attaches lsp client when bib found", content = entry },
		{ name = "attaches lsp client when no bib file", content = nil },
	})
	:each(function(c)
		T["lsp_start"][c.name] = function()
			local dir = u.temp_dir()
			local md = vim.fs.joinpath(dir, "paper.md")
			if c.content then u.write_file(child, vim.fs.joinpath(dir, "refs.bib"), c.content) end
			u.write_file(child, md, c.content and "---\nbibliography: refs.bib\n---\nSee @smith2020." or "# No bib")
			child.lua(string.format("vim.cmd.edit(%q)", md))
			child.lua("require('bib').setup({ zotero = { database = '/tmp/nonexistent.sqlite' } })")
			local has = child.lua_get("(function() for _, c in ipairs(vim.lsp.get_clients({bufnr=0})) do if c.name == 'bib_ls' then return true end end; return false end)()")
			eq(has, true)
		end
	end)

local function setup_handler(md_content)
	local dir = u.temp_dir()
	u.write_file(child, vim.fs.joinpath(dir, "refs.bib"), entry)
	local md = vim.fs.joinpath(dir, "paper.md")
	u.write_file(child, md, md_content)
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua("require('bib').setup({ zotero = { database = '/tmp/nonexistent.sqlite' } })")
	child.lua("require('bib.lsp').pick(vim.api.nvim_get_current_buf())")
	return dir
end

T["lsp_handlers"] = test.new_set()

local completion_kind = 18

T["lsp_handlers"]["completion returns items matching prefix"] = function()
	local dir = setup_handler("---\nbibliography: refs.bib\n---\n\nSee @smi")
	local r = u.lsp_request(child, "textDocument/completion", { line = 4, character = 7 })
	eq(r.err, vim.NIL)
	eq(#r.result.items, 1)
	eq(r.result.items[1].textEdit.newText, "smith2020")
	eq(r.result.items[1].kind, completion_kind)
end

T["lsp_handlers"]["completion returns empty when no key"] = function()
	setup_handler("---\nbibliography: refs.bib\n---\n\nSee no key here")
	local r = u.lsp_request(child, "textDocument/completion", { line = 3, character = 10 })
	eq(r.err, vim.NIL)
	eq(#r.result.items, 0)
end

T["lsp_handlers"]["definition returns bib file location"] = function()
	local dir = setup_handler("---\nbibliography: refs.bib\n---\n\nSee @smith2020")
	local r = u.lsp_request(child, "textDocument/definition", { line = 4, character = 12 }, false)
	eq(r.err, vim.NIL)
	eq(r.result.uri, vim.uri_from_fname(vim.fs.joinpath(dir, "refs.bib")))
	eq(r.result.range.start.line, 0)
end

T["lsp_handlers"]["hover returns formatted content"] = function()
	setup_handler("---\nbibliography: refs.bib\n---\n\nSee @smith2020")
	local r = u.lsp_request(child, "textDocument/hover", { line = 4, character = 12 }, false)
	eq(r.err, vim.NIL)
	local value = r.result.contents.value
	eq(value:find("John Smith") ~= nil, true)
	eq(value:find("Test") ~= nil, true)
	eq(value:find("2020") ~= nil, true)
end

T["lsp_handlers"]["completion returns empty inside code fence"] = function()
	setup_handler("---\nbibliography: refs.bib\n---\n\n```markdown\n@smi\n```\n\nSee @smi")
	local r = u.lsp_request(child, "textDocument/completion", { line = 4, character = 4 })
	eq(r.err, vim.NIL)
	eq(#r.result.items, 0)
end

T["lsp_handlers"]["code action returns pdf and note for zotero citation"] = function()
	local dir = u.temp_dir()
	local db_path = u.setup_zotero_db(child, dir)
	local md = vim.fs.joinpath(dir, "paper.md")
	u.write_file(child, md, "# Hello\n\nSee @ABC123#smith2020.")
	child.lua(string.format("vim.cmd.edit(%q)", md))
	child.lua(string.format("require('bib').setup({ zotero = { database = %q } })", db_path))
	child.lua("require('bib.lsp').pick(vim.api.nvim_get_current_buf())")

	eq(child.lua_get("type(require('bib.lsp').backend())"), "table")
	eq(child.lua_get("require('bib.utils.lsp').citekey_at(vim.api.nvim_get_current_buf(), 2, 13)"), "ABC123#smith2020")

	child.lua([[
		_G._result = nil
		local server = require("bib.lsp").server()
		server.request("textDocument/codeAction", {
			textDocument = { uri = vim.uri_from_bufnr(0) },
			range = { start = { line = 2, character = 13 }, ["end"] = { line = 2, character = 22 } },
		}, function(err, result)
			_G._result = { err = err or vim.NIL, result = result or vim.NIL }
		end)
	]])

	local r = child.lua_get("_G._result")
	eq(r.err, vim.NIL)
	eq(#r.result, 2)

	local titles = vim.iter(r.result):map(function(a) return a.title end):totable()
	eq(titles[1], "Open PDF")
	eq(titles[2], "Get notes from Zotero")
end

return T
