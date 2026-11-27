local ts = require("bib.ts")
local markdown_frontmatter, yaml_field

---@type table
local yaml = {}

--- Get a field from YAML frontmatter
---@param field string Frontmatter field name.
---@param bufnr integer Buffer that contains the document.
---@return string|nil value Field value, or nil if absent.
---@return string|nil error Parser or cleanup error, or nil on success.
function yaml.field(field, bufnr)
  if vim.bo[bufnr].filetype == "tex" then return end

  local ok, parser, err = pcall(vim.treesitter.get_parser, bufnr, "markdown")
  if not ok then return nil, tostring(parser) end
  if not parser then return nil, err or "Could not create Markdown parser" end

  local query = markdown_frontmatter
  if not query then
    query, err = ts.load("markdown", "frontmatter")
    if err ~= nil then return nil, err end
    if not query then return nil, "Could not load Markdown frontmatter query" end
    markdown_frontmatter = query
  end

  local value
  ok, value, err = pcall(function()
    local matches = query:iter_matches(parser:parse()[1]:root(), bufnr, 0, -1)
    local found, failure
    vim.iter(matches):find(function(_, match)
      found, failure = yaml.parse_text(vim.treesitter.get_node_text(match[1][1], bufnr), field)
      return found ~= nil or failure ~= nil
    end)
    return found, failure
  end)

  if not ok then return nil, tostring(value) end
  return value, err
end

--- Extract a field value from YAML text
---@param text string YAML text to parse.
---@param field string Field name to find.
---@return string|nil value Field value, or nil if absent.
---@return string|nil error Parser or cleanup error, or nil on success.
function yaml.parse_text(text, field)
  local ok, buf = pcall(vim.api.nvim_create_buf, false, true)
  if not ok then return nil, tostring(buf) end
  local result, query_err

  ok, result, query_err = pcall(function()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n"))
    local parser, err = vim.treesitter.get_parser(buf, "yaml")
    if not parser then return nil, err or "Could not create YAML parser" end

    local query = yaml_field
    if not query then
      query, err = ts.load("yaml", "field")
      if err ~= nil then return nil, err end
      if not query then return nil, "Could not load YAML field query" end
      yaml_field = query
    end
    local root = parser:parse()[1]:root()
    local field_matches = require("bib.utils.yaml").field_matches

    return ts.fold(query, root, buf, nil, field_matches(buf, field))
  end)

  local deleted, cleanup_err = pcall(vim.api.nvim_buf_delete, buf, { force = true })
  local failure = not ok and tostring(result) or query_err

  if failure ~= nil then
    if not deleted then vim.lsp.log.warn("[bib] scratch buffer cleanup failed: " .. tostring(cleanup_err)) end
    return nil, failure
  end

  if not deleted then return nil, tostring(cleanup_err) end

  return result
end

return yaml
