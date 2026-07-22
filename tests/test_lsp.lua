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

T["lsp_handlers"]["completion returns items matching prefix"] = function()
	local dir = setup_handler("---\nbibliography: refs.bib\n---\n\nSee @smi")
	local r = u.lsp_request(child, "textDocument/completion", { line = 4, character = 7 })
	eq(r.err, vim.NIL)
	eq(#r.result.items, 1)
	eq(r.result.items[1].textEdit.newText, "smith2020")
	eq(r.result.items[1].kind, 18)
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

return T
