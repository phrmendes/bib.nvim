local test = require("mini.test")
local u = dofile("tests/utils.lua")
local eq = test.expect.equality

local child, T = u.new_child_set()

local entry = "@article{smith2020,\n  author = {John Smith},\n  title = {Test},\n  year = {2020}\n}"

T["lsp_start"] = test.new_set()

vim
	.iter({
		{ name = "attaches lsp client when bib found", content = entry, expected = true },
		{ name = "stops client when no backend available", content = nil, expected = false },
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
			eq(has, c.expected)
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

T["lsp_handlers"]["initialize advertises utf-8 position encoding"] = function()
	setup_handler("---\nbibliography: refs.bib\n---\n\nSee @smith2020")
	local result = child.lua([[
		local server = require('bib.lsp').server({ on_exit = function() end })
		local result
		server.request('initialize', { capabilities = {} }, function(_, value) result = value end)
		return result
	]])
	eq(result.capabilities.positionEncoding, "utf-8")
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

T["lsp_handlers"]["keeps separate backends per buffer"] = function()
	local dir_a = u.temp_dir()
	local dir_b = u.temp_dir()
	u.write_file(child, vim.fs.joinpath(dir_a, "a.bib"), "@article{alpha, title = {Alpha}}")
	u.write_file(child, vim.fs.joinpath(dir_b, "b.bib"), "@article{beta, title = {Beta}}")

	local md_a = vim.fs.joinpath(dir_a, "a.md")
	local md_b = vim.fs.joinpath(dir_b, "b.md")
	u.write_file(child, md_a, "---\nbibliography: a.bib\n---\n")
	u.write_file(child, md_b, "---\nbibliography: b.bib\n---\n")

	child.lua("require('bib').setup({ zotero = { database = '/tmp/nonexistent.sqlite' } })")

	child.lua(string.format("vim.cmd.edit(%q)", md_a))
	local buf_a = child.lua_get("vim.api.nvim_get_current_buf()")
	child.lua(string.format("require('bib.lsp').pick(%d)", buf_a))

	child.lua(string.format("vim.cmd.edit(%q)", md_b))
	local buf_b = child.lua_get("vim.api.nvim_get_current_buf()")
	child.lua(string.format("require('bib.lsp').pick(%d)", buf_b))

	eq(child.lua_get(string.format("require('bib.lsp').backend(%d).get('alpha') ~= nil", buf_a)), true)
	eq(child.lua_get(string.format("require('bib.lsp').backend(%d).get('beta') ~= nil", buf_b)), true)
	eq(child.lua_get(string.format("require('bib.lsp').backend(%d).get('beta')", buf_a)), vim.NIL)
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
