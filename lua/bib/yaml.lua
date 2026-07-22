local q = require("bib.ts.queries")

---@type table
local yaml = {}

--- Get a field from YAML frontmatter
---@param field string
---@param bufnr integer
---@return string|nil
function yaml.field(field, bufnr)
	if vim.bo[bufnr].filetype == "tex" then return end

	local parser = vim.treesitter.get_parser(bufnr, "markdown")
	if not parser then return end

	local matches = q.markdown_frontmatter:iter_matches(parser:parse()[1]:root(), bufnr, 0, -1)
	return vim.iter(matches):map(function(_, match) return yaml.parse_text(vim.treesitter.get_node_text(match[1][1], bufnr), field) end):find(function(v) return v end)
end

--- Extract a field value from YAML text
---@param text string
---@param field string
---@return string|nil
function yaml.parse_text(text, field)
	local ts = require("bib.ts")

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n"))

	local parser = vim.treesitter.get_parser(buf, "yaml")

	if not parser or not q.yaml_field then
		vim.api.nvim_buf_delete(buf, { force = true })
		return
	end

	local root = parser:parse()[1]:root()

	local field_matches = require("bib.utils.yaml").field_matches
	local result = ts.fold(q.yaml_field, root, buf, nil, field_matches(buf, field))

	vim.api.nvim_buf_delete(buf, { force = true })
	return result
end

return yaml
