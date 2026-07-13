local q = require("bib.query")
local queries = require("bib.queries")

local yaml = {}

local field_query = queries.yaml_field
local fm_query = queries.markdown_frontmatter

--- Get a field from YAML frontmatter
---@param field string
---@param bufnr integer
---@return string|nil
function yaml.field(field, bufnr)
	if vim.bo[bufnr].filetype == "tex" then return nil end

	local parser = vim.treesitter.get_parser(bufnr, "markdown")
	if not parser then return nil end

	local matches = fm_query:iter_matches(parser:parse()[1]:root(), bufnr, 0, -1)
	return vim.iter(matches):map(function(_, match) return yaml.parse_text(vim.treesitter.get_node_text(match[1][1], bufnr), field) end):find(function(v) return v end)
end

--- Extract a field value from YAML text
---@param text string
---@param field string
---@return string|nil
function yaml.parse_text(text, field)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n"))

	local parser = vim.treesitter.get_parser(buf, "yaml")
	if not parser or not field_query then
		vim.api.nvim_buf_delete(buf, { force = true })
		return nil
	end

	local root = parser:parse()[1]:root()
	local result = q.fold_matches(field_query, root, buf, nil, function(acc, match, ids)
		if acc then return acc end
		local key_node = match[ids["key"]][1]
		local value_node = match[ids["value"]][1]
		if key_node and value_node and vim.treesitter.get_node_text(key_node, buf) == field then return vim.treesitter.get_node_text(value_node, buf) end
		return acc
	end)

	vim.api.nvim_buf_delete(buf, { force = true })
	return result
end

return yaml
