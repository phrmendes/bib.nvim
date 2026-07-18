local patterns = require("bib.patterns")

---@type table
local lsp = {}

--- Get text from a node, optionally truncated to cursor column
---@param node TSNode
---@param bufnr integer
---@param col integer|nil
---@return string
local function node_text(node, bufnr, col)
	local text = vim.treesitter.get_node_text(node, bufnr)

	if not col then return text end

	local _, start_col = node:start()
	return text:sub(1, col - start_col)
end

---@type table<string, fun(node: TSNode, bufnr: integer, prefix_col: integer|nil, full_col: integer|nil): string|nil>
local citation_extractors = {
	curly_group_text = function(node, bufnr, prefix_col) return node_text(node, bufnr, prefix_col) end,
	inline = function(node, bufnr, prefix_col, full_col)
		if prefix_col then return node_text(node, bufnr, prefix_col):match(patterns.inline_partial) end

		local _, start_col = node:start()
		local text = vim.treesitter.get_node_text(node, bufnr)
		local pos = full_col - start_col + 1

		local prefix = text:sub(1, pos - 1):match(patterns.key_left)
		if not prefix then return nil end

		local rest = text:sub(pos):match(patterns.key_right)
		if not rest then return nil end

		return prefix .. rest
	end,
}

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

--- Extract position fields from an LSP textDocument params object
---@param params table
---@return integer lnum
---@return integer char
---@return integer bufnr
function lsp.pos(params) return params.position.line, params.position.character, vim.uri_to_bufnr(params.textDocument.uri) end

--- Extract citation key at the LSP request position
---@param params table
---@return string|nil
function lsp.key(params)
	local lnum, char, bufnr = lsp.pos(params)
	return lsp.key_at(bufnr, lnum, char)
end

--- Extract a citation key at cursor position
---@param bufnr integer
---@param lnum integer 0-indexed line
---@param col integer 0-indexed column
---@param partial? boolean Return only the partial key before cursor
---@return string|nil
function lsp.key_at(bufnr, lnum, col, partial) return extract_key(bufnr, lnum, col, partial) end

return lsp
