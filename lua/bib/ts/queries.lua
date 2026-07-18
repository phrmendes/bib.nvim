local ts = require("bib.ts")
local u = require("bib.utils")

---@type table<string, vim.treesitter.Query>
return u.lazy({
	bibtex_strings = function() return ts.load("bibtex", "strings") end,
	bibtex_entries = function() return ts.load("bibtex", "entries") end,
	yaml_field = function() return ts.load("yaml", "field") end,
	markdown_frontmatter = function() return ts.load("markdown", "frontmatter") end,
	latex_bibliography = function() return ts.load("latex", "bibliography") end,
})
