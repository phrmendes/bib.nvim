local patterns = require("bib.patterns")
---@type table<string, vim.treesitter.Query>
local queries = require("bib.ts.queries")
local ts = require("bib.ts")
local u = require("bib.utils")

---@type table
local backends = {}

---@type table<string, fun(bufnr: integer, dir: string): string|nil>
local finders

---@type table<string, fun(node: TSNode, bufnr: integer, dir: string): string|nil>
local extractors

local function extract_curly_arg(node, bufnr)
	return vim.iter(node:iter_children()):fold(nil, function(acc, c)
		if acc then return acc end
		if c:type():find("curly_group") or c:type() == "path" then return vim.treesitter.get_node_text(c, bufnr):sub(2, -2) end
		return extract_curly_arg(c, bufnr)
	end)
end

extractors = {
	bibtex_include = function(node, bufnr, dir)
		local arg = extract_curly_arg(node, bufnr)
		return arg and u.resolve_path(dir, arg .. ".bib")
	end,
	line_comment = function(node, bufnr, dir)
		local text = vim.treesitter.get_node_text(node, bufnr)
		local root_file = text:match(patterns.tex_root)
		if not root_file then return nil end
		local rootpath = u.resolve_path(dir, root_file)
		if not rootpath then return nil end
		if vim.fn.filereadable(rootpath) ~= 1 then return nil end
		local rootbuf = vim.fn.bufadd(rootpath)
		vim.fn.bufload(rootbuf)
		local result = backends.find_tex_bib(vim.fn.fnamemodify(rootpath, ":p:h"), rootbuf)
		vim.api.nvim_buf_delete(rootbuf, { force = true })
		return result
	end,
}

finders = {
	markdown = function(bufnr, dir)
		local yaml = require("bib.yaml")
		local ybib = yaml.field("bibliography", bufnr)
		return ybib and u.resolve_path(dir, ybib)
	end,
	tex = function(bufnr, dir) return backends.find_tex_bib(dir, bufnr) end,
}

--- Read a SQL query from the sql/ directory
---@param name string
---@return string
function backends.read_sql(name)
	local files = vim.api.nvim_get_runtime_file("sql/" .. name .. ".sql", false)
	if #files == 0 then return "" end
	return table.concat(vim.fn.readfile(files[1]), "\n")
end

--- Extract @string macros from the AST
---@param buf integer
---@param root TSNode
---@return table<string, string>
function backends.collect_strings(buf, root)
	local ids = ts.capture_ids(queries.bibtex_strings)
	local matches = queries.bibtex_strings:iter_matches(root, buf, 0, -1)
	return vim.iter(matches):fold({}, function(strings, _, match)
		local name_node = match[ids["name"]][1]
		local value_node = match[ids["value"]][1]
		if not name_node or not value_node then return strings end
		local name = vim.trim(vim.treesitter.get_node_text(name_node, buf))
		local value = u.strip_value(vim.treesitter.get_node_text(value_node, buf))
		if name ~= "" then strings[name] = value end
		return strings
	end)
end

--- Resolve @string references in a value
---@param value string
---@param strings table<string, string>
---@return string
function backends.resolve(value, strings)
	value = u.strip_value(value)
	local resolved = strings[value]
	if resolved then return resolved end
	return table.concat(vim
		.iter(vim.split(value, patterns.concat_sep))
		:map(function(part)
			if not part then return "" end
			local s = u.strip_value(part)
			local found = strings[s]
			return found or s
		end)
		:totable())
end

--- Extract entries from the AST
---@param buf integer
---@param root TSNode
---@param strings table<string, string>
---@return table<string, BibEntry>
function backends.collect_entries(buf, root, strings)
	local ids = ts.capture_ids(queries.bibtex_entries)
	local matches = queries.bibtex_entries:iter_matches(root, buf, 0, -1)
	return vim.iter(matches):fold({}, function(result, _, match)
		local type_node = match[ids["type"]][1]
		local key_node = match[ids["key"]][1]
		local name_node = match[ids["name"]][1]
		local value_node = match[ids["value"]][1]

		if not type_node or not key_node or not name_node or not value_node then return result end
		local key = vim.treesitter.get_node_text(key_node, buf)
		local fname = vim.trim(vim.treesitter.get_node_text(name_node, buf)):lower()
		local fvalue = backends.resolve(vim.treesitter.get_node_text(value_node, buf), strings)

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
function backends.parse(path)
	local buf = vim.fn.bufadd(path)
	vim.fn.bufload(buf)

	local parser = vim.treesitter.get_parser(buf, "bibtex")
	if not parser then
		vim.api.nvim_buf_delete(buf, { force = true })
		return nil
	end

	local root = parser:parse()[1]:root()
	local strings = backends.collect_strings(buf, root)
	local result = backends.collect_entries(buf, root, strings)

	vim.api.nvim_buf_delete(buf, { force = true })
	return result
end

--- Find .bib file path from buffer configuration
---@param bufnr integer
---@return string|nil
function backends.find_bib_file(bufnr)
	local bufname = vim.api.nvim_buf_get_name(bufnr)
	if bufname == "" then return nil end
	local dir = vim.fn.fnamemodify(bufname, ":p:h")

	local finder = finders[vim.bo[bufnr].filetype]
	if finder then
		local result = finder(bufnr, dir)
		if result then return result end
	end

	local root = vim.fs.root(bufname, ".bib.json")
	if not root then return nil end

	local json_path = vim.fs.joinpath(root, ".bib.json")
	local ok, data = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(json_path), "\n")) end)
	if ok and data and data.bibliography then return u.resolve_path(root, data.bibliography) end

	return nil
end

--- Find .bib file for LaTeX documents using tree-sitter
---@param dir string
---@param bufnr integer
---@return string|nil
function backends.find_tex_bib(dir, bufnr)
	local parser = vim.treesitter.get_parser(bufnr, "latex")
	if not parser then return nil end
	local root = parser:parse()[1]:root()
	local matches = queries.latex_bibliography:iter_matches(root, bufnr, 0, -1)

	return vim
		.iter(matches)
		:map(function(_, match)
			return vim
				.iter(vim.tbl_values(match))
				:map(function(nodes) return nodes[1] end)
				:map(function(node)
					local f = extractors[node:type()]
					return f and f(node, bufnr, dir)
				end)
				:find(function(path) return path ~= nil end)
		end)
		:find(function(path) return path ~= nil end)
end

--- Find the Zotero database path from config or default
---@return string|nil
function backends.find_zotero_db()
	local cfg = require("bib.config").get()
	if cfg.zotero and cfg.zotero.database then return cfg.zotero.database end
	return vim.fs.joinpath(vim.env.HOME, "Zotero", "zotero.sqlite")
end

return backends
