local q = require("bib.query")
local queries = require("bib.queries")
local utils = require("bib.utils")

local backend_utils = {}

--- Read a SQL query from the sql/ directory
---@param name string
---@return string
function backend_utils.read_sql(name)
	local files = vim.api.nvim_get_runtime_file("sql/" .. name .. ".sql", false)
	if #files == 0 then return "" end
	return table.concat(vim.fn.readfile(files[1]), "\n")
end

--- Extract @string macros from the AST
---@param buf integer
---@param root TSNode
---@return table<string, string>
function backend_utils.collect_strings(buf, root)
	local ids = q.capture_ids(queries.bibtex_strings)
	local matches = queries.bibtex_strings:iter_matches(root, buf, 0, -1)
	return vim.iter(matches):fold({}, function(strings, _, match)
		local name_node = match[ids["name"]][1]
		local value_node = match[ids["value"]][1]
		if not name_node or not value_node then return strings end
		local name = vim.trim(vim.treesitter.get_node_text(name_node, buf))
		local value = utils.strip_value(vim.treesitter.get_node_text(value_node, buf))
		if name ~= "" then strings[name] = value end
		return strings
	end)
end

--- Extract entries from the AST
---@param buf integer
---@param root TSNode
---@param strings table<string, string>
---@return table<string, BibEntry>
function backend_utils.collect_entries(buf, root, strings)
	local ids = q.capture_ids(queries.bibtex_entries)
	local matches = queries.bibtex_entries:iter_matches(root, buf, 0, -1)
	return vim.iter(matches):fold({}, function(result, _, match)
		local type_node = match[ids["type"]][1]
		local key_node = match[ids["key"]][1]
		local name_node = match[ids["name"]][1]
		local value_node = match[ids["value"]][1]

		if not type_node or not key_node or not name_node or not value_node then return result end
		local key = vim.treesitter.get_node_text(key_node, buf)
		local fname = vim.trim(vim.treesitter.get_node_text(name_node, buf)):lower()
		local fvalue = utils.resolve_value(vim.treesitter.get_node_text(value_node, buf), strings)

		if result[key] then
			result[key].fields[fname] = fvalue
			return result
		end

		local etype = vim.treesitter.get_node_text(type_node, buf):sub(2):lower()

		result[key] = {
			key = key,
			type = etype,
			fields = { [fname] = fvalue },
			line = type_node:start() + 1,
		}
		return result
	end)
end

--- Parse a .bib file using tree-sitter
---@param path string
---@return table<string, BibEntry>|nil
function backend_utils.parse(path)
	local buf = vim.fn.bufadd(path)
	vim.fn.bufload(buf)

	local parser = vim.treesitter.get_parser(buf, "bibtex")
	if not parser then
		vim.api.nvim_buf_delete(buf, { force = true })
		return nil
	end

	local root = parser:parse()[1]:root()
	local strings = backend_utils.collect_strings(buf, root)
	local result = backend_utils.collect_entries(buf, root, strings)

	vim.api.nvim_buf_delete(buf, { force = true })
	return result
end

return backend_utils
