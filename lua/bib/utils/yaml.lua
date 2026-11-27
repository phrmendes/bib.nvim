---@type table
local yaml = {}

--- Find the first YAML key matching `field` in a tree-sitter query match and return its value.
---@param buf integer Buffer that contains the YAML tree.
---@param field string Field name to find.
---@return fun(acc: string|nil, match: table, ids: table<string, integer>): string|nil matcher Function that returns the first matching field value.
function yaml.field_matches(buf, field)
  return function(acc, match, ids)
    if acc then return acc end

    local key = match[ids.key][1]
    local value = match[ids.value][1]
    if key and value and vim.treesitter.get_node_text(key, buf) == field then return vim.treesitter.get_node_text(value, buf) end

    return acc
  end
end

return yaml
