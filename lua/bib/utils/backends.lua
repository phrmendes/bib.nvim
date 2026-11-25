local patterns = require("bib.patterns")
local queries = require("bib.ts.queries")
local ts = require("bib.ts")

--- Strip surrounding braces or quotes from a value
---@param value string
---@return string
local function strip_value(value)
	value = vim.trim(value)
	local pairs = { ["{"] = "}", ['"'] = '"' }
	local open = value:sub(1, 1)
	if pairs[open] == value:sub(-1, -1) then return value:sub(2, -2) end
	return value
end

--- Recursively extract text from a curly_group or path node
---@param node TSNode
---@param bufnr integer
---@return string|nil
local function extract_curly_arg(node, bufnr)
	return vim.iter(node:iter_children()):fold(nil, function(acc, c)
		if acc then return acc end
		if c:type():find("curly_group") or c:type() == "path" then return vim.treesitter.get_node_text(c, bufnr):sub(2, -2) end
		return extract_curly_arg(c, bufnr)
	end)
end

--- Load file contents into a private scratch buffer, so no user buffer changes.
---@param path string
---@return integer
local function load_scratch(path)
	local lines = vim.fn.filereadable(path) == 1 and vim.fn.readfile(path) or {}
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	return buf
end

---@type table
local backends = {}

--- Tree-sitter node type → .bib path extractor for LaTeX documents
---@type table<string, fun(node: TSNode, bufnr: integer, dir: string): string|nil>
local extractors = {
	bibtex_include = function(node, bufnr, dir)
		local arg = extract_curly_arg(node, bufnr)
		return arg and backends.resolve_path(dir, arg .. ".bib")
	end,
	line_comment = function(node, bufnr, dir)
		local text = vim.treesitter.get_node_text(node, bufnr)
		local root_file = text:match(patterns.tex_root)
		if not root_file then return end
		local rootpath = backends.resolve_path(dir, root_file)
		if not rootpath then return end
		if vim.fn.filereadable(rootpath) ~= 1 then return end
		local rootbuf = load_scratch(rootpath)
		local result = backends.find_tex_bib(vim.fn.fnamemodify(rootpath, ":p:h"), rootbuf)
		vim.api.nvim_buf_delete(rootbuf, { force = true })
		return result
	end,
}

--- Find .bib path from a .bib.json marker file
---@param base string
---@return string|nil
local function find_json_bib(base)
	local json_path = vim.fs.joinpath(base, ".bib.json")
	local ok, data = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(json_path), "\n")) end)
	if ok and data and data.bibliography then return backends.resolve_path(base, data.bibliography) end
end

--- Process a tree-sitter match to extract a .bib path from LaTeX
---@param match table
---@param bufnr integer
---@param dir string
---@return string|nil
local function process_tex_match(match, bufnr, dir)
	return vim
		.iter(vim.tbl_values(match))
		:map(function(nodes)
			local node = nodes[1]
			local f = extractors[node:type()]
			return f and f(node, bufnr, dir)
		end)
		:find(function(path) return path ~= nil end)
end

--- Filetype → .bib path finder strategy
---@type table<string, fun(bufnr: integer, dir: string): string|nil>
local finders = {
	markdown = function(bufnr, dir)
		local yaml = require("bib.yaml")
		local ybib = yaml.field("bibliography", bufnr)
		return ybib and backends.resolve_path(dir, ybib)
	end,
	tex = function(bufnr, dir) return backends.find_tex_bib(dir, bufnr) end,
}

--- Resolve a relative path against a base directory
---@param base string
---@param path string
---@return string|nil
function backends.resolve_path(base, path)
	if not path or path == "" or path:sub(1, 1) == "/" or path:sub(2, 2) == ":" then return path end
	return vim.fn.fnamemodify(base .. "/" .. path, ":p")
end

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
		local name_node = match[ids.name][1]
		local value_node = match[ids.value][1]
		if not name_node or not value_node then return strings end
		local name = vim.trim(vim.treesitter.get_node_text(name_node, buf))
		local value = strip_value(vim.treesitter.get_node_text(value_node, buf))
		if name ~= "" then strings[name] = value end
		return strings
	end)
end

--- Split a BibTeX value on top-level `#` only. Braces and quotes nest, so
--- `{C# in Depth}` stays whole while `"a" # "b"` splits in two.
---@param value string
---@return string[]
local function split_concat(value)
	local parts, depth, quote, start, i = {}, 0, nil, 1, 1

	while i <= #value do
		local ch = value:sub(i, i)

		if quote then
			if ch == "\\" then
				i = i + 1
			elseif ch == quote then
				quote = nil
			end
		elseif ch == '"' then
			quote = ch
		elseif ch == "{" then
			depth = depth + 1
		elseif ch == "}" then
			depth = depth - 1
		elseif ch == "#" and depth == 0 then
			table.insert(parts, value:sub(start, i - 1))
			start = i + 1
		end

		i = i + 1
	end

	table.insert(parts, value:sub(start))
	return parts
end

--- Resolve @string references in a value
---@param value string
---@param strings table<string, string>
---@return string
function backends.resolve(value, strings)
	local whole = strip_value(value)
	local resolved = strings[whole]
	if resolved then return resolved end

	local parts = split_concat(value)

	if #parts == 1 then return whole end

	return vim.iter(parts):fold("", function(acc, part)
		local s = strip_value(part)
		return acc .. (strings[s] or s)
	end)
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
		local type_node = match[ids.type][1]
		local key_node = match[ids.key][1]
		local name_node = match[ids.name][1]
		local value_node = match[ids.value][1]

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
	local buf = load_scratch(path)

	local parser = vim.treesitter.get_parser(buf, "bibtex")
	if not parser then
		vim.api.nvim_buf_delete(buf, { force = true })
		return
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
	if bufname == "" then return end
	local dir = vim.fn.fnamemodify(bufname, ":p:h")

	local finder = finders[vim.bo[bufnr].filetype]
	if finder then
		local result = finder(bufnr, dir)
		if result then return result end
	end

	local root = vim.fs.root(bufname, ".bib.json")
	if root then return find_json_bib(root) end
end

--- Find .bib file for LaTeX documents using tree-sitter
---@param dir string
---@param bufnr integer
---@return string|nil
function backends.find_tex_bib(dir, bufnr)
	local parser = vim.treesitter.get_parser(bufnr, "latex")
	if not parser then return end
	local root = parser:parse()[1]:root()
	local matches = queries.latex_bibliography:iter_matches(root, bufnr, 0, -1)

	return vim.iter(matches):map(function(_, match) return process_tex_match(match, bufnr, dir) end):find(function(path) return path ~= nil end)
end

--- Loaders for search commands
---@type table
backends.load = {
	--- Load entries from the .bib file for the current buffer
	---@return table[]|nil
	bib = function()
		local bib = require("bib.backends.bib")
		if pcall(bib.load, vim.api.nvim_get_current_buf()) then
			local entries = bib.all()
			if #entries > 0 then return entries end
		end
	end,
	--- Load entries from the Zotero database
	---@return table[]|nil
	zotero = function()
		local zotero = require("bib.backends.zotero")
		if not pcall(zotero.load) then return nil end
		return zotero.all()
	end,
}

--- Find the Zotero database path from config or default
---@return string|nil
function backends.find_zotero_db()
	local cfg = require("bib").get()
	if cfg and cfg.zotero and cfg.zotero.database then return cfg.zotero.database end
	return vim.fs.joinpath(vim.env.HOME, "Zotero", "zotero.sqlite")
end

return backends
