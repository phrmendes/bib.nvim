local ts = require("bib.ts")

---@type table<string, vim.treesitter.Query>
return {
	bibtex_strings = ts.load("bibtex", "strings"),
	bibtex_entries = ts.load("bibtex", "entries"),
	yaml_field = ts.load("yaml", "field"),
	markdown_frontmatter = ts.load("markdown", "frontmatter"),
	latex_bibliography = ts.load("latex", "bibliography"),
}
