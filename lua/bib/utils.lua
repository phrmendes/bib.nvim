local patterns = require("bib.patterns")
local queries = require("bib.queries")
local yaml = require("bib.yaml")

local utils = {}

--- Get text from a node, optionally truncated to cursor column
---@param node TSNode
---@param bufnr integer
---@param col integer|nil
---@return string
local function node_text(node, bufnr, col)
	local text = vim.treesitter.get_node_text(node, bufnr)
	if col then
		local _, start_col = node:start()
		return text:sub(1, col - start_col)
	end
	return text
end

--- Extract a citation key word at a character position
---@param text string
---@param pos integer 1-indexed position within text
---@return string|nil
local function word_at(text, pos)
	local prefix = text:sub(1, pos - 1):match(patterns.key_left)
	if not prefix then return nil end
	local suffix = text:sub(pos)
	local rest = suffix:match(patterns.key_right)
	if not rest then return nil end
	return prefix .. rest
end

---@type table<string, fun(node: TSNode, bufnr: integer, prefix_col: integer|nil, full_col: integer|nil): string|nil>
local citation_extractors = {
	curly_group_text = function(node, bufnr, prefix_col) return node_text(node, bufnr, prefix_col) end,
	inline = function(node, bufnr, prefix_col, full_col)
		if prefix_col then return node_text(node, bufnr, prefix_col):match(patterns.inline_partial) end
		local _, start_col = node:start()
		return word_at(vim.treesitter.get_node_text(node, bufnr), full_col - start_col + 1)
	end,
}

---@type table<string, fun(bufnr: integer, dir: string): string|nil>
local finders = {
	markdown = function(bufnr, dir)
		local ybib = yaml.field("bibliography", bufnr)
		return ybib and utils.resolve_path(dir, ybib)
	end,
	tex = function(bufnr, dir) return utils.find_tex_bib(dir, bufnr) end,
}

---@type table<string, fun(node: TSNode, bufnr: integer, dir: string): string|nil>
local tex_bib_extractors

local function extract_curly_arg(node, bufnr)
	return vim.iter(node:iter_children()):fold(nil, function(acc, c)
		if acc then return acc end
		if c:type():find("curly_group") or c:type() == "path" then return vim.treesitter.get_node_text(c, bufnr):sub(2, -2) end
		return extract_curly_arg(c, bufnr)
	end)
end

tex_bib_extractors = {
	bibtex_include = function(node, bufnr, dir)
		local arg = extract_curly_arg(node, bufnr)
		return arg and utils.resolve_path(dir, arg .. ".bib")
	end,
	line_comment = function(node, bufnr, dir)
		local text = vim.treesitter.get_node_text(node, bufnr)
		local root_file = text:match(patterns.tex_root)
		if not root_file then return nil end
		local rootpath = utils.resolve_path(dir, root_file)
		if not rootpath then return nil end
		if vim.fn.filereadable(rootpath) ~= 1 then return nil end
		local rootbuf = vim.fn.bufadd(rootpath)
		vim.fn.bufload(rootbuf)
		local result = utils.find_tex_bib(vim.fn.fnamemodify(rootpath, ":p:h"), rootbuf)
		vim.api.nvim_buf_delete(rootbuf, { force = true })
		return result
	end,
}

--- Strip surrounding braces or quotes from a value
---@param value string
---@return string
function utils.strip_value(value)
	value = vim.trim(value)
	local pairs = { ["{"] = "}", ['"'] = '"' }
	local open = value:sub(1, 1)
	if pairs[open] == value:sub(-1, -1) then return value:sub(2, -2) end
	return value
end

--- Resolve @string references in a value
---@param value string
---@param strings table<string, string>
---@return string
function utils.resolve_value(value, strings)
	value = utils.strip_value(value)
	local resolved = strings[value]
	if resolved then return resolved end
	return table.concat(vim
		.iter(vim.split(value, patterns.concat_sep))
		:map(function(part)
			if not part then return "" end
			local s = utils.strip_value(part)
			local found = strings[s]
			return found or s
		end)
		:totable())
end

--- Resolve a relative path against a base directory
---@param base string
---@param path string
---@return string|nil
function utils.resolve_path(base, path)
	if not path or path == "" or path:sub(1, 1) == "/" or path:sub(2, 2) == ":" then return path end
	return vim.fn.fnamemodify(base .. "/" .. path, ":p")
end

--- Walk up from cursor position to find and extract a citation key
---@param bufnr integer
---@param lnum integer
---@param col integer
---@param partial boolean|nil
---@return string|nil
local function extract_key(bufnr, lnum, col, partial)
	local lang = vim.bo[bufnr].filetype == "tex" and "latex" or "markdown"
	vim.treesitter.get_parser(bufnr, lang):parse()
	local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { lnum, col } })
	while node do
		local fn = citation_extractors[node:type()]
		if fn then
			local result = fn(node, bufnr, partial and col or nil, col)
			if result then return result end
		end
		node = node:parent()
	end
end

--- Extract a citation key at cursor position
---@param bufnr integer
---@param lnum integer 0-indexed line
---@param col integer 0-indexed column
---@param partial? boolean Return only the partial key before cursor
---@return string|nil
function utils.key_at(bufnr, lnum, col, partial) return extract_key(bufnr, lnum, col, partial) end

--- Find .bib file path from buffer configuration
---@param bufnr integer
---@return string|nil
function utils.find_bib_file(bufnr)
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
	if ok and data and data.bibliography then return utils.resolve_path(root, data.bibliography) end

	return nil
end

--- Find .bib file for LaTeX documents using tree-sitter
---@param dir string
---@param bufnr integer
---@return string|nil
function utils.find_tex_bib(dir, bufnr)
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
					local extract = tex_bib_extractors[node:type()]
					return extract and extract(node, bufnr, dir)
				end)
				:find(function(path) return path ~= nil end)
		end)
		:find(function(path) return path ~= nil end)
end

return utils
