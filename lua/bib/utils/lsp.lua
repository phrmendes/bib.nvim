local patterns = require("bib.patterns")

---@type table
local lsp = {}

---@type table<string, fun(node: TSNode, bufnr: integer, prefix_col: integer|nil, full_col: integer, lnum: integer): string|nil>
local extractors

--- Get text from a node, optionally truncated to cursor column
---@param node TSNode Tree-sitter node.
---@param bufnr integer Buffer that contains the node.
---@param col integer|nil Zero-indexed byte column, or nil for the full text.
---@return string text Node text up to the requested column.
---@private
local function node_text(node, bufnr, col)
  local text = vim.treesitter.get_node_text(node, bufnr)

  if not col then return text end

  local _, start_col = node:start()
  return text:sub(1, col - start_col)
end

--- Extract a citation key from a LaTeX node.
---@param node TSNode Tree-sitter node to inspect.
---@param bufnr integer Buffer that contains the node.
---@param prefix_col integer|nil Zero-indexed byte column, or nil for the full key.
---@return string|nil key Citation key, or nil outside a citation.
---@private
local function tex_citation(node, bufnr, prefix_col)
  local parent = node:parent()
  if parent and parent:type() == "curly_group_text_list" then parent = parent:parent() end
  if parent and parent:type() == "citation" then return node_text(node, bufnr, prefix_col) end
end

extractors = {
  curly_group_text = tex_citation,
  text = tex_citation,
  inline = function(node, bufnr, prefix_col, full_col, lnum)
    local start_row, start_col = node:start()
    local end_row, end_col = node:end_()
    local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1] or ""
    local offset = lnum == start_row and start_col or 0
    local text = line:sub(offset + 1, lnum == end_row and end_col or #line)
    if prefix_col then return text:sub(1, prefix_col - offset):match(patterns.inline_partial) end

    local pos = full_col - offset + 1
    local prefix = text:sub(1, pos - 1):match(patterns.key_left)
    if not prefix then return end

    local rest = text:sub(pos):match(patterns.key_right)
    if not rest then return end

    return prefix .. rest
  end,
}

--- Walk up from cursor position to find and extract a citation key
---@param bufnr integer Buffer handle.
---@param lnum integer Zero-indexed line.
---@param col integer Zero-indexed byte column.
---@param partial boolean|nil Return only the key before the cursor when true.
---@return string|nil key Citation key, or nil if absent.
---@return string|nil error Parser error, or nil on success.
---@private
local function extract_key(bufnr, lnum, col, partial)
  local lang = vim.bo[bufnr].filetype == "tex" and "latex" or "markdown"
  local parser, err = vim.treesitter.get_parser(bufnr, lang)
  if not parser then return nil, err or ("Could not create " .. lang .. " parser") end
  parser:parse()
  local node = vim.treesitter.get_node({ bufnr = bufnr, lang = lang, pos = { lnum, col } })
  while node do
    local fn = extractors[node:type()]
    if fn then
      local result = fn(node, bufnr, partial and col or nil, col, lnum)
      if result then return result end
    end

    node = node:parent()
  end
end

--- Extract position fields from an LSP textDocument params object
---@param params table LSP document position parameters.
---@return integer lnum Zero-indexed line.
---@return integer char Zero-indexed byte column.
---@return integer bufnr Buffer handle.
function lsp.position(params) return params.position.line, params.position.character, vim.uri_to_bufnr(params.textDocument.uri) end

--- Extract citation key at the LSP request position
---@param params table LSP document position parameters.
---@return string|nil key Citation key, or nil if absent.
---@return string|nil error Parser error, or nil on success.
function lsp.citekey(params)
  local lnum, char, bufnr = lsp.position(params)
  return lsp.citekey_at(bufnr, lnum, char)
end

--- Extract a citation key at cursor position
---@param bufnr integer Buffer handle.
---@param lnum integer 0-indexed line
---@param col integer 0-indexed column
---@param partial? boolean Return only the partial key before cursor
---@return string|nil key Citation key, or nil if absent.
---@return string|nil error Parser error, or nil on success.
function lsp.citekey_at(bufnr, lnum, col, partial) return extract_key(bufnr, lnum, col, partial) end

return lsp
