local patterns = require("bib.patterns")
local find_zotero_db = require("bib.utils.backends").find_zotero_db
local db_utils = require("bib.utils.sqlite")
local read_sql = db_utils.read_sql
local close_db = db_utils.close_db

---@type table
local zotero = {}

---@type {entries: table<string, ZoteroEntry>, copy: {path: string|nil}}
local state = {
  entries = {},
  copy = { path = nil },
}

--- Create the snapshot path when needed.
---@return string|nil path Path for the local snapshot, or nil on failure.
---@return string|nil error Directory creation error, or nil on success.
---@private
local function init_snapshot()
  if state.copy.path then return state.copy.path end

  local tmpdir = vim.fn.tempname()
  local ok, err = vim.uv.fs_mkdir(tmpdir, 448)
  if not ok then return nil, err or "could not create snapshot directory" end

  local snapshot = vim.fs.joinpath(tmpdir, "zotero.db")
  local register_result

  if snapshot ~= nil then
    ok, register_result = pcall(vim.api.nvim_create_autocmd, "VimLeavePre", {
      once = true,
      callback = function() vim.fn.delete(tmpdir, "rf") end,
    })
  end

  if snapshot == nil or not ok then
    local cleanup_err
    ok, cleanup_err = pcall(vim.fn.delete, tmpdir, "rf")
    if not ok or cleanup_err ~= 0 then vim.lsp.log.warn("[bib] temporary directory cleanup failed: " .. tostring(cleanup_err)) end
    return nil, snapshot == nil and "Could not initialize Zotero snapshot path" or tostring(register_result)
  end

  state.copy.path = snapshot
  return state.copy.path
end

--- Remove a temporary snapshot.
---@param tmp string Path to the temporary snapshot.
---@private
local function remove_tmp(tmp)
  local removed, err, code = vim.uv.fs_unlink(tmp)
  if not removed and code ~= "ENOENT" then vim.lsp.log.warn("[bib] temporary snapshot cleanup failed: " .. tostring(err or "unknown error")) end
end

--- Preserve the primary error and report cleanup errors.
---@param failure string|nil Primary error, or nil if none occurred.
---@param message string Cleanup error to record.
---@return string error Primary error, or the cleanup error.
---@private
local function record_failure(failure, message)
  if failure ~= nil then
    vim.lsp.log.warn("[bib] cleanup failed: " .. message)
    return failure
  end

  return message
end

--- Finish an unfinished backup and record any error.
---@param defs table SQLite backup functions.
---@param backup any Unfinished backup handle, or nil.
---@param flags {ok: integer, done: integer} SQLite result codes.
---@param failure string|nil Primary error, or nil if none occurred.
---@return string|nil error Primary or cleanup error, or nil on success.
---@private
local function finish_backup(defs, backup, flags, failure)
  if backup == nil then return failure end

  local finished, result = pcall(defs.backup_finish, backup)
  if not finished then return record_failure(failure, "backup cleanup failed: " .. tostring(result)) end
  if result ~= flags.ok then return record_failure(failure, "backup cleanup failed: SQLite code " .. tostring(result)) end

  return failure
end

--- Close both DBs and preserve the primary error.
---@param source sqlite_db|nil Source DB handle, or nil.
---@param destination sqlite_db|nil Destination DB handle, or nil.
---@param failure string|nil Primary error, or nil if none occurred.
---@return string|nil error Primary or close error, or nil on success.
---@private
local function close_dbs(source, destination, failure)
  local err
  if source then
    err = close_db(source)
    if err ~= nil then failure = record_failure(failure, "source close failed: " .. err) end
  end

  if destination then
    err = close_db(destination)
    if err ~= nil then failure = record_failure(failure, "destination close failed: " .. err) end
  end

  return failure
end

--- Copy the source DB into a temporary snapshot.
---@param sqlite table SQLite module.
---@param defs table SQLite backup functions.
---@param db_path string Path to the source Zotero DB.
---@param tmp string Path for the temporary snapshot.
---@return string|nil error Snapshot error, or nil on success.
---@private
local function snapshot_db(sqlite, defs, db_path, tmp)
  ---@type {ok: integer, done: integer}
  local flags = defs.flags
  local source, destination, backup, failure

  local ok, err = pcall(function()
    source = sqlite.new(db_path, { open_mode = "ro", busy_timeout = 500 })
    destination = sqlite.new(tmp)

    source:open()
    destination:open()

    backup = defs.backup_init(destination.conn, "main", source.conn, "main")

    if backup == nil then error(defs.last_errmsg(destination.conn)) end

    local result = defs.backup_step(backup, -1)
    local finished = defs.backup_finish(backup)

    backup = nil

    if result ~= flags.done or finished ~= flags.ok then error("SQLite backup failed: " .. defs.last_errmsg(destination.conn)) end

    destination:eval("PRAGMA journal_mode=DELETE")
  end)

  if not ok then failure = "failed to snapshot Zotero database: " .. tostring(err) end

  failure = finish_backup(defs, backup, flags, failure)
  failure = close_dbs(source, destination, failure)

  return failure
end

--- Read items and creators from the snapshot.
---@param sqlite table SQLite module.
---@param tmp string Path to the temporary snapshot.
---@return {items: table[], creators: table[]}|nil rows Item and creator rows, or nil on failure.
---@return string|nil error Query error, or nil on success.
---@private
local function query_db(sqlite, tmp)
  local db, failure

  local queried, items, creators = pcall(function()
    db = sqlite.new(tmp)
    db:open()
    return db:eval(read_sql("items")), db:eval(read_sql("creators"))
  end)

  if not queried then failure = tostring(items) end

  if db then
    local err = close_db(db)
    if err ~= nil then failure = record_failure(failure, "snapshot close failed: " .. err) end
  end

  if failure ~= nil then return nil, failure end

  if type(creators) ~= "table" then creators = {} end
  if type(items) ~= "table" or #items == 0 then return nil, "zotero database is empty" end

  return { items = items, creators = creators }
end

--- Build Zotero entries from item and creator rows.
---@param items table[] Item rows from the snapshot.
---@param creators table[] Creator rows from the snapshot.
---@return table<string, ZoteroEntry> entries Entries indexed by Zotero item key.
---@private
local function make_entries(items, creators)
  local entries = {}
  local item_to_key = {}

  vim.iter(items):each(function(row)
    local key = row.key
    if not entries[key] then entries[key] = { key = key, type = row.typeName, fields = {} } end
    entries[key].fields[row.fieldName] = row.value
    item_to_key[row.itemID] = key
  end)

  vim.iter(creators):each(function(row)
    local key = item_to_key[row.itemID]
    if not key or not entries[key] then return end

    local name = vim.trim((row.firstName or "") .. " " .. (row.lastName or ""))
    local e = entries[key]
    local existing = e.creators or {}
    existing[row.creatorType] = existing[row.creatorType] and existing[row.creatorType] .. ", " .. name or name
    e.creators = existing
    if row.creatorType == "author" then e.fields.author = existing[row.creatorType] end
  end)

  vim.iter(pairs(entries)):each(function(itemID, entry)
    local citekey = entry.fields.citationKey

    if citekey then
      entry.key = itemID .. "#" .. citekey
      entry.citekey = citekey
    else
      entry.key = itemID .. "#" .. itemID
      entry.citekey = itemID
    end

    entry.zotkey = itemID

    if entry.fields.date then entry.fields.year = entry.fields.date:match(patterns.year) end
  end)

  return entries
end

--- Build entries and replace the local snapshot.
---@param sqlite table SQLite module.
---@param defs table SQLite backup functions.
---@param db_path string Path to the source Zotero DB.
---@param tmp string Path for the temporary snapshot.
---@param snapshot string Path for the local snapshot.
---@return table<string, ZoteroEntry>|nil entries Entries indexed by Zotero item key, or nil on failure.
---@return string|nil error Snapshot or query error, or nil on success.
---@private
local function load_snapshot(sqlite, defs, db_path, tmp, snapshot)
  local err = snapshot_db(sqlite, defs, db_path, tmp)
  if err ~= nil then return nil, err end

  local rows
  rows, err = query_db(sqlite, tmp)
  if rows == nil then return nil, err or "Could not read Zotero snapshot rows" end

  local entries = make_entries(rows.items, rows.creators)
  local renamed
  renamed, err = vim.uv.fs_rename(tmp, snapshot)
  if not renamed then return nil, "failed to replace Zotero snapshot: " .. tostring(err or "unknown error") end

  return entries
end

--- Path of the local Zotero database copy, if it exists
---@return string|nil path Snapshot path, or the configured DB path before loading.
function zotero.db_path() return state.copy.path or find_zotero_db() end

--- Load state.entries from Zotero SQLite database
---@return string|nil error Load error, or nil on success.
function zotero:load()
  local ok, sqlite = pcall(require, "sqlite")
  if not ok then return tostring(sqlite) end

  local db_path = find_zotero_db()
  if not db_path then return "zotero database not found" end

  local stat, err, code = vim.uv.fs_stat(db_path)

  if not stat then
    if err ~= nil and code ~= "ENOENT" then return "cannot read Zotero database: " .. err end
    return "zotero database not found"
  end

  local snapshot
  snapshot, err = init_snapshot()
  if snapshot == nil then return err or "Could not initialize Zotero snapshot path" end

  local defs
  ok, defs = pcall(require, "sqlite.defs")
  if not ok then return tostring(defs) end

  local tmp = snapshot .. ".new"
  local removed

  removed, err, code = vim.uv.fs_unlink(tmp)
  if not removed and code ~= "ENOENT" then return "failed to remove temporary snapshot: " .. tostring(err or "unknown error") end

  local entries
  ok, entries, err = pcall(load_snapshot, sqlite, defs, db_path, tmp, snapshot)

  if not ok or entries == nil then
    remove_tmp(tmp)
    if not ok then return tostring(entries) end
    return err or "Could not build Zotero entries"
  end

  state.entries = entries
end

--- Get state.entries matching a prefix (case-insensitive, matches citekey)
---@param prefix string Case-insensitive citation key prefix.
---@return ZoteroEntry[] entries Matching entries.
function zotero:match(prefix)
  local lower = prefix:lower()
  return vim.iter(pairs(state.entries)):filter(function(_, e) return e.citekey:lower():find(lower, 1, true) == 1 end):map(function(_, e) return e end):totable()
end

--- Search entries by substring (case-insensitive, matches citekey/title/author)
---@param query string Case-insensitive text to find.
---@return ZoteroEntry[] entries Matching entries.
function zotero:search(query)
  local lower = query:lower()
  return vim
    .iter(pairs(state.entries))
    :filter(function(_, e)
      if e.citekey:lower():find(lower, 1, true) then return true end
      if e.fields.title and e.fields.title:lower():find(lower, 1, true) then return true end
      if e.fields.author and e.fields.author:lower():find(lower, 1, true) then return true end

      return false
    end)
    :map(function(_, e) return e end)
    :totable()
end

--- Get a single entry by composite key
---@param key string Zotero item key or composite citation key.
---@return ZoteroEntry|nil entry Matching entry, or nil if absent.
function zotero:get(key) return state.entries[key:gsub(patterns.zotkey_strip, "")] end

--- Get all entries
---@return ZoteroEntry[] entries All loaded entries.
function zotero:all()
  return vim.iter(pairs(state.entries)):map(function(_, e) return e end):totable()
end

--- Get go-to-definition URI for a key
---@param key string Zotero item key or composite citation key.
---@return {uri: string}|nil location Zotero URI, or nil if absent.
function zotero:definition(key)
  local zotkey = key:gsub(patterns.zotkey_strip, "")
  if not state.entries[zotkey] then return end

  return { uri = "zotero://select/library/items/" .. zotkey }
end

--- Get hover content for a key
---@param key string Zotero item key or composite citation key.
---@return string|nil text Markdown content, or nil if absent.
function zotero:hover(key)
  local zotkey = key:gsub(patterns.zotkey_strip, "")
  local entry = state.entries[zotkey]
  if not entry then return end

  local header = {}

  if entry.creators and entry.creators.author then table.insert(header, entry.creators.author) end
  if entry.fields.title then table.insert(header, entry.fields.title) end

  if entry.fields.date then
    local year = entry.fields.date:match(patterns.year)
    table.insert(header, year or entry.fields.date)
  end

  local parts = { "# " .. table.concat(header, " - ") }

  if entry.fields.abstractNote then
    local abstract = entry.fields.abstractNote:gsub(patterns.whitespace, " ")
    table.insert(parts, "---\n" .. abstract)
  end

  return table.concat(parts, "\n\n")
end

return zotero
