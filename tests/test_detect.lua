local test = require("mini.test")
local tu = dofile("tests/utils.lua")
local eq = test.expect.equality

local child, T = tu.new_child_set()

T["find_bib_file"] = test.new_set()

vim
	.iter({
		{
			name = "finds bib from yaml frontmatter",
			content = "---\ntitle: My Paper\nbibliography: refs.bib\n---\n\n# Intro\n",
			bib_json = nil,
			expected_getter = function(dir) return vim.fs.joinpath(dir, "refs.bib") end,
		},
		{
			name = "finds bib from .bib.json",
			content = "# Intro\n\nNo yaml header here.\n",
			bib_json = '{"bibliography": "refs.bib"}',
			expected_getter = function(dir) return vim.fs.joinpath(dir, "refs.bib") end,
		},
		{
			name = "returns nil when no bib configured",
			content = "# Intro\n\nJust text.\n",
			bib_json = nil,
			expected_getter = function() return vim.NIL end,
		},
		{
			name = "yaml takes priority over .bib.json",
			content = "---\nbibliography: yaml-refs.bib\n---\n\n# Intro\n",
			bib_json = '{"bibliography": "json-refs.bib"}',
			extra_files = { { "yaml-refs.bib", "@article{yaml, title = {From YAML}}" }, { "json-refs.bib", "@article{json, title = {From JSON}}" } },
			expected_getter = function(dir) return vim.fs.joinpath(dir, "yaml-refs.bib") end,
		},
	})
	:each(function(c)
		T["find_bib_file"][c.name] = function()
			local dir = tu.temp_dir()
			local md = vim.fs.joinpath(dir, "paper.md")
			if c.extra_files then vim.iter(c.extra_files):each(function(f) tu.write_file(child, vim.fs.joinpath(dir, f[1]), f[2]) end) end
			tu.write_file(child, vim.fs.joinpath(dir, "refs.bib"), "@article{test, title = {Test}}")
			tu.write_file(child, md, c.content)
			if c.bib_json then tu.write_file(child, vim.fs.joinpath(dir, ".bib.json"), c.bib_json) end
			child.lua(string.format("vim.cmd.edit(%q)", md))
			eq(child.lua_get("require('bib.utils').find_bib_file(vim.api.nvim_get_current_buf())"), c.expected_getter(dir))
		end
	end)

T["find_tex_bib"] = test.new_set()

vim
	.iter({
		{
			name = "finds bibliography command",
			content = "\\documentclass{article}\n\\begin{document}\nHello\n\\bibliography{refs}\n\\end{document}\n",
			expected_getter = function(dir) return vim.fs.joinpath(dir, "refs.bib") end,
		},
	})
	:each(function(c)
		T["find_tex_bib"][c.name] = function()
			local dir = tu.temp_dir()
			local tex = vim.fs.joinpath(dir, "paper.tex")
			tu.write_file(child, vim.fs.joinpath(dir, "refs.bib"), "@article{test, title = {Test}}")
			tu.write_file(child, tex, c.content)
			child.lua(string.format("vim.cmd.edit(%q)", tex))
			child.lua(string.format("_G._bib_dir = %q", dir))
			eq(child.lua_get("require('bib.utils').find_tex_bib(_G._bib_dir, vim.api.nvim_get_current_buf())"), c.expected_getter(dir))
		end
	end)

return T
