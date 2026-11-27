---@type table
local sqlite = {}

--- Close a DB and return any error.
---@param db sqlite_db DB handle to close.
---@return string|nil error Close error, or nil on success.
function sqlite.close_db(db)
  local ok, result, err = pcall(db.close, db)
  if not ok then return tostring(result) end
  if err ~= nil then return tostring(err) end
  if result == false then return "close returned false" end
end

--- Read a SQL query from the sql/ directory.
---@param name string SQL file name without its extension.
---@return string sql Query text, or an empty string if absent.
function sqlite.read_sql(name)
  local files = vim.api.nvim_get_runtime_file("sql/" .. name .. ".sql", false)
  if #files == 0 then return "" end

  return table.concat(vim.fn.readfile(files[1]), "\n")
end

return sqlite
