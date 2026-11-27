local patterns = require("bib.patterns")
local ts = require("bib.ts")
local bibtex_strings, bibtex_entries, latex_bibliography

---@type table
local backends = {}

--- Tree-sitter node type → .bib path extractor for LaTeX documents
---@type table<string, fun(node: TSNode, bufnr: integer, dir: string): string|nil, string|nil>
local extractors

--- Filetype → .bib path finder strategy
---@type table<string, fun(bufnr: integer, dir: string): string|nil, string|nil>
local finders = {
  markdown = function(bufnr, dir)
    local yaml = require("bib.yaml")
    local ybib, err = yaml.field("bibliography", bufnr)
    if err ~= nil then return nil, err end

    return ybib and backends.resolve_path(dir, ybib)
  end,
  tex = function(bufnr, dir) return backends.find_tex_bib(dir, bufnr) end,
}

--- Strip surrounding braces or quotes from a value
---@param value string BibTeX value to unwrap.
---@return string text Value without matching outer delimiters.
---@private
local function strip_value(value)
  value = vim.trim(value)
  local pairs = { ["{"] = "}", ['"'] = '"' }
  local open = value:sub(1, 1)
  if pairs[open] == value:sub(-1, -1) then return value:sub(2, -2) end

  return value
end

--- Recursively extract text from a curly_group or path node
---@param node TSNode Node to search.
---@param bufnr integer Buffer that contains the node.
---@return string|nil text Argument text, or nil if absent.
---@private
local function extract_curly_arg(node, bufnr)
  return vim
    .iter(node:iter_children())
    :map(function(child)
      if child:type():find("curly_group") or child:type() == "path" then return vim.treesitter.get_node_text(child, bufnr):sub(2, -2) end

      return extract_curly_arg(child, bufnr)
    end)
    :next()
end

--- Read a file, or return empty lines when it is missing.
---@param path string File to read.
---@return string[]|nil lines File lines, or nil on failure.
---@return string|nil error Read error, or nil on success.
---@private
local function read_lines(path)
  if vim.fn.filereadable(path) == 1 then
    local ok, lines = pcall(vim.fn.readfile, path)
    if not ok then return nil, tostring(lines) end
    return lines
  end

  local stat, err, code = vim.uv.fs_stat(path)
  if err ~= nil and code ~= "ENOENT" then return nil, "cannot read " .. path .. ": " .. err end
  if stat then return nil, "cannot read " .. path end
  return {}
end

--- Read a file through a temporary buffer.
---@param path string File to read.
---@param callback fun(buf: integer): any, string|nil Function that receives the temporary buffer.
---@return any result Callback result, or nil on failure.
---@return string|nil error Read, callback, or cleanup error.
---@private
local function with_scratch(path, callback)
  local lines, err = read_lines(path)
  if not lines then return nil, err end

  local ok, buf = pcall(vim.api.nvim_create_buf, false, true)
  if not ok then return nil, tostring(buf) end

  local result, callback_err
  ok, result, callback_err = pcall(function()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    return callback(buf)
  end)

  local deleted, cleanup_err = pcall(vim.api.nvim_buf_delete, buf, { force = true })
  local failure = not ok and tostring(result) or callback_err

  if not deleted then
    if failure == nil then return nil, tostring(cleanup_err) end
    vim.lsp.log.warn("[bib] scratch buffer cleanup failed: " .. tostring(cleanup_err))
  end

  if failure ~= nil then return nil, failure end

  return result
end

extractors = {
  bibtex_include = function(node, bufnr, dir)
    local arg = extract_curly_arg(node, bufnr)
    return arg and backends.resolve_path(dir, arg .. ".bib")
  end,
  biblatex_include = function(node, bufnr, dir)
    local arg = extract_curly_arg(node, bufnr)
    return arg and backends.resolve_path(dir, arg)
  end,
  line_comment = function(node, bufnr, dir)
    local text = vim.treesitter.get_node_text(node, bufnr)
    local root_file = text:match(patterns.tex_root)
    if not root_file then return end

    local rootpath = backends.resolve_path(dir, root_file)
    if not rootpath then return end
    if vim.fn.filereadable(rootpath) ~= 1 then return end

    return with_scratch(rootpath, function(rootbuf) return backends.find_tex_bib(vim.fn.fnamemodify(rootpath, ":p:h"), rootbuf) end)
  end,
}

--- Find .bib path from a .bib.json marker file
---@param base string Directory containing the marker file.
---@return string|nil path Bibliography path, or nil if not configured.
---@private
local function find_json_bib(base)
  local json_path = vim.fs.joinpath(base, ".bib.json")
  local ok, data = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(json_path), "\n")) end)
  if ok and data and data.bibliography then return backends.resolve_path(base, data.bibliography) end
end

--- Process a tree-sitter match to extract a .bib path from LaTeX
---@param match table Tree-sitter query match.
---@param bufnr integer Buffer that contains the match.
---@param dir string Directory used to resolve relative paths.
---@return string|nil path Bibliography path, or nil if not found.
---@return string|nil error Extraction error, or nil on success.
---@private
local function process_tex_match(match, bufnr, dir)
  local path, err

  vim.iter(pairs(match)):find(function(_, nodes)
    local node = nodes[1]
    local f = extractors[node:type()]

    if f then
      path, err = f(node, bufnr, dir)
    end

    return path ~= nil or err ~= nil
  end)

  return path, err
end

--- Split a BibTeX value on top-level `#` only. Braces and quotes nest, so
--- `{C# in Depth}` stays whole while `"a" # "b"` splits in two.
---@param value string BibTeX value expression.
---@return string[] parts Top-level concatenation parts.
---@private
local function split_concat(value)
  local state = vim.iter(value:gmatch("()(.)")):fold({
    parts = {},
    start = 1,
    depth = 0,
    quoted = false,
    escaped = false,
  }, function(acc, i, char)
    if acc.escaped then
      acc.escaped = false
    elseif acc.quoted and char == "\\" then
      acc.escaped = true
    elseif char == '"' then
      acc.quoted = not acc.quoted
    elseif not acc.quoted then
      if char == "{" then
        acc.depth = acc.depth + 1
      elseif char == "}" then
        acc.depth = acc.depth - 1
      elseif char == "#" and acc.depth == 0 then
        table.insert(acc.parts, value:sub(acc.start, i - 1))
        acc.start = i + 1
      end
    end

    return acc
  end)

  table.insert(state.parts, value:sub(state.start))
  return state.parts
end

--- Resolve a relative path against a base directory
---@param base string Base directory for relative paths.
---@param path string Path to resolve.
---@return string|nil path Resolved path, or nil when no path is provided.
function backends.resolve_path(base, path)
  if not path or path == "" or path:sub(1, 1) == "/" or path:sub(2, 2) == ":" then return path end

  return vim.fn.fnamemodify(base .. "/" .. path, ":p")
end

--- Extract @string macros from the AST
---@param buf integer Buffer that contains the bibliography.
---@param root TSNode Root node of the bibliography tree.
---@return table<string, string>|nil strings Macro names mapped to values, or nil on failure.
---@return string|nil error Query error, or nil on success.
function backends.collect_strings(buf, root)
  local query = bibtex_strings

  if not query then
    local err
    query, err = ts.load("bibtex", "strings")
    if err ~= nil then return nil, err end
    if not query then return nil, "Could not load BibTeX strings query" end
    bibtex_strings = query
  end

  local ok, result = pcall(ts.fold, query, root, buf, {}, function(strings, match, ids)
    local name_node = match[ids.name][1]
    local value_node = match[ids.value][1]
    if not name_node or not value_node then return strings end

    local name = vim.trim(vim.treesitter.get_node_text(name_node, buf))
    local value = strip_value(vim.treesitter.get_node_text(value_node, buf))
    if name ~= "" then strings[name] = value end
    return strings
  end)

  if not ok then return nil, tostring(result) end
  return result
end

--- Resolve @string references in a value
---@param value string BibTeX value expression.
---@param strings table<string, string> Macro names mapped to values.
---@return string text Resolved value.
function backends.resolve(value, strings)
  return vim.iter(split_concat(value)):fold("", function(acc, part)
    part = vim.trim(part)
    local first = part:sub(1, 1)
    if first == "{" or first == '"' then return acc .. strip_value(part) end

    return acc .. (strings[part] or part)
  end)
end

--- Extract entries from the AST
---@param buf integer Buffer that contains the bibliography.
---@param root TSNode Root node of the bibliography tree.
---@param strings table<string, string> Macro names mapped to values.
---@return table<string, BibEntry>|nil entries Entries indexed by citation key, or nil on failure.
---@return string|nil error Query error, or nil on success.
function backends.collect_entries(buf, root, strings)
  local query = bibtex_entries

  if not query then
    local err
    query, err = ts.load("bibtex", "entries")
    if err ~= nil then return nil, err end
    if not query then return nil, "Could not load BibTeX entries query" end
    bibtex_entries = query
  end

  local ok, collected = pcall(ts.fold, query, root, buf, {}, function(result, match, ids)
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

  if not ok then return nil, tostring(collected) end
  return collected
end

--- Parse a .bib file using tree-sitter
---@param path string Bibliography file path.
---@return table<string, BibEntry>|nil entries Entries indexed by citation key, or nil on failure.
---@return string|nil error Parse or cleanup error, or nil on success.
function backends.parse(path)
  return with_scratch(path, function(buf)
    local parser, err = vim.treesitter.get_parser(buf, "bibtex")
    if not parser then return nil, err or "Could not create BibTeX parser" end

    local root = parser:parse()[1]:root()
    local strings
    strings, err = backends.collect_strings(buf, root)
    if err ~= nil then return nil, err end
    if not strings then return nil, "Could not collect BibTeX strings" end
    return backends.collect_entries(buf, root, strings)
  end)
end

--- Find .bib file path from buffer configuration
---@param bufnr integer Buffer whose bibliography is resolved.
---@return string|nil path Bibliography path, or nil if not configured.
---@return string|nil error Resolution error, or nil on success.
function backends.find_bib_file(bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if bufname == "" then return end

  local dir = vim.fn.fnamemodify(bufname, ":p:h")

  local finder = finders[vim.bo[bufnr].filetype]
  if finder then
    local result, err = finder(bufnr, dir)
    if err ~= nil then return nil, err end
    if result then return result end
  end

  local root = vim.fs.root(bufname, ".bib.json")
  if root then return find_json_bib(root) end
end

--- Find .bib file for LaTeX documents using tree-sitter
---@param dir string Directory used to resolve relative paths.
---@param bufnr integer Buffer that contains the LaTeX document.
---@return string|nil path Bibliography path, or nil if not found.
---@return string|nil error Query or extraction error, or nil on success.
function backends.find_tex_bib(dir, bufnr)
  local ok, parser, err = pcall(vim.treesitter.get_parser, bufnr, "latex")
  if not ok then return nil, tostring(parser) end
  if not parser then return nil, err or "Could not create LaTeX parser" end

  local root
  ok, root = pcall(function() return parser:parse()[1]:root() end)
  if not ok then return nil, tostring(root) end

  local query = latex_bibliography
  if not query then
    query, err = ts.load("latex", "bibliography")
    if err ~= nil then return nil, err end
    if not query then return nil, "Could not load LaTeX bibliography query" end
    latex_bibliography = query
  end

  local path
  ok, path, err = pcall(function()
    local matches = query:iter_matches(root, bufnr, 0, -1)
    local found, failure
    vim.iter(matches):find(function(_, match)
      found, failure = process_tex_match(match, bufnr, dir)
      return found ~= nil or failure ~= nil
    end)
    return found, failure
  end)

  if not ok then return nil, tostring(path) end
  return path, err
end

--- Loaders for search commands
---@type table
backends.load = {
  --- Load the .bib backend for the current buffer
  ---@return Backend|nil backend Loaded backend, or nil if no entries are available.
  ---@return string|nil error Load error, or nil on success.
  bib = function()
    local bib = require("bib.backends.bib")
    local backend, err = bib.load(vim.api.nvim_get_current_buf())
    if err ~= nil then return nil, err end
    if backend and #backend:all() > 0 then return backend end
  end,
  --- Load the Zotero backend
  ---@return Backend|nil backend Loaded backend, or nil if loading fails.
  ---@return string|nil error Load error, or nil on success.
  zotero = function()
    local zotero = require("bib.backends.zotero")
    local err = zotero:load()
    if err ~= nil then return nil, err end

    return zotero
  end,
}

--- Find the Zotero database path from config or default
---@return string|nil path Configured or default Zotero DB path.
function backends.find_zotero_db()
  local cfg = require("bib").get()
  if cfg and cfg.zotero and cfg.zotero.database then return cfg.zotero.database end

  return vim.fs.joinpath(vim.env.HOME, "Zotero", "zotero.sqlite")
end

return backends
