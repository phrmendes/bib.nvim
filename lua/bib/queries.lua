local query = require("bib.query")

local loaders = {
	bibtex_strings = function() return query.load_query("bibtex", "strings") end,
	bibtex_entries = function() return query.load_query("bibtex", "entries") end,
	yaml_field = function() return query.load_query("yaml", "field") end,
	markdown_frontmatter = function() return query.load_query("markdown", "frontmatter") end,
	latex_bibliography = function() return query.load_query("latex", "bibliography") end,
}

local queries = setmetatable({}, {
	__index = function(t, k)
		local loader = loaders[k]
		if not loader then return nil end
		local v = loader()
		rawset(t, k, v)
		return v
	end,
})

return queries
