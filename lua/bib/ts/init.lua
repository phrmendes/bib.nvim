---@type table
local ts = {}

--- Load a tree-sitter query from a .scm file on the runtimepath
---@param lang string Tree-sitter language
---@param name string Query file name without extension
---@return vim.treesitter.Query|nil query Parsed Tree-sitter query, or nil on failure.
---@return string|nil error Query load error, or nil on success.
function ts.load(lang, name)
  local path = "queries/" .. lang .. "/" .. name .. ".scm"
  local ok, files = pcall(vim.api.nvim_get_runtime_file, path, false)
  if not ok then return nil, tostring(files) end
  local file = files[1]
  if not file then return nil, "query not found: " .. path end

  local query
  ok, query = pcall(function()
    local content = table.concat(vim.fn.readfile(file), "\n")
    return vim.treesitter.query.parse(lang, content)
  end)

  if not ok then return nil, tostring(query) end
  return query
end

--- Build reverse lookup: capture name -> capture ID
---@param q {captures: table<integer, string>} Query whose captures are indexed.
---@return table<string, integer> ids Capture names mapped to numeric IDs.
function ts.capture_ids(q)
  return vim.iter(pairs(q.captures)):fold({}, function(ids, id, name)
    ids[name] = id
    return ids
  end)
end

--- Run a tree-sitter query and fold results into an accumulator
---@generic T
---@param q vim.treesitter.Query Query to run.
---@param root TSNode Root node to search.
---@param buf integer Buffer that contains the tree.
---@param initial T Initial accumulator.
---@param fn fun(acc: T, match: table, ids: table): T Function that combines a match with the accumulator.
---@return T result Final accumulator.
function ts.fold(q, root, buf, initial, fn)
  local ids = ts.capture_ids(q)
  local matches = q:iter_matches(root, buf, 0, -1)

  return vim.iter(matches):fold(initial, function(acc, _, match) return fn(acc, match, ids) end)
end

return ts
