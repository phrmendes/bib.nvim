local backends = require("bib.utils.backends")
local db_utils = require("bib.utils.sqlite")
local patterns = require("bib.patterns")

---@type table
local actions = {}

--- Read attachments and notes through an open database handle.
---@param db sqlite_db Open Zotero DB handle.
---@param entry BibEntry|ZoteroEntry Citation entry with a Zotero key.
---@return {actions: table[], notes: table|boolean} result Code actions and note rows.
---@private
local function query_zotero(db, entry)
  local result = {}

  local pdfs = db:eval(db_utils.read_sql("attachments"), { key = entry.zotkey })

  if type(pdfs) == "table" and #pdfs > 0 then
    local pdf_path = pdfs[1].path

    if pdf_path:find(patterns.storage_prefix) then pdf_path = vim.fs.joinpath(vim.fs.dirname(backends.find_zotero_db()), "storage", pdfs[1].attachKey, pdf_path:sub(9)) end

    result[#result + 1] = {
      title = "Open PDF",
      kind = "quickfix",
      command = {
        title = "Open",
        command = "bib.open_pdf",
        arguments = { pdf_path },
      },
    }
  end

  return { actions = result, notes = db:eval(db_utils.read_sql("notes"), { key = entry.zotkey }) }
end

--- Read actions and notes from a Zotero database.
---@param db_path string Path to the Zotero database.
---@param entry BibEntry|ZoteroEntry Citation entry with a Zotero key.
---@return {actions: table[], notes: table|boolean}|nil result Code actions and notes, or nil on failure.
---@return lsp.ResponseError|nil error DB close error, or nil otherwise.
---@private
local function read_zotero(db_path, entry)
  local db, close_err
  local ok, err = pcall(function()
    db = require("sqlite").new(db_path)
    db:open({ busy_timeout = 500 })
  end)

  if not ok or not db then
    if db then
      close_err = db_utils.close_db(db)
      if close_err ~= nil then vim.lsp.log.warn("[bib] database close failed: " .. close_err) end
    end

    vim.notify("[bib] could not open the Zotero database: " .. tostring(err), vim.log.levels.ERROR)
    return
  end

  local result
  ok, result = pcall(query_zotero, db, entry)
  close_err = db_utils.close_db(db)

  if not ok then
    if close_err ~= nil then vim.lsp.log.warn("[bib] database close failed: " .. tostring(close_err)) end
    vim.notify("[bib] code action failed: " .. tostring(result), vim.log.levels.ERROR)
    return
  end

  if close_err ~= nil then return nil, { code = vim.lsp.protocol.ErrorCodes.InternalError, message = "database close failed: " .. tostring(close_err) } end

  return result
end

--- Convert notes and append their code action.
---@param items table[] Existing code actions.
---@param notes table|boolean Zotero note rows, or a boolean when no rows exist.
---@param params table LSP code action params.
---@param callback fun(actions: table[]|nil, err?: lsp.ResponseError) Receives actions or an LSP error.
---@private
local function append_notes(items, notes, params, callback)
  if type(notes) ~= "table" or #notes == 0 then return callback(items) end

  local lines = {}
  --- Convert Zotero notes into a code action.
  ---@param index integer One-indexed note to convert.
  ---@private
  local function convert(index)
    if index > #notes then
      if #lines > 0 then lines[#lines] = nil end
      items[#items + 1] = {
        title = "Get notes from Zotero",
        kind = "refactor",
        edit = {
          changes = {
            [params.textDocument.uri] = {
              {
                range = {
                  start = { line = params.range["end"].line + 1, character = 0 },
                  ["end"] = { line = params.range["end"].line + 1, character = 0 },
                },
                newText = table.concat(lines, "\n") .. "\n",
              },
            },
          },
        },
      }

      return callback(items)
    end

    local note = notes[index].note

    require("bib.utils.notes").to_markdown(note, function(body)
      local success, convert_err = pcall(function()
        vim.list_extend(lines, vim.split(body or note, "\n"))
        lines[#lines + 1] = ""
        convert(index + 1)
      end)

      if not success then callback(nil, { code = vim.lsp.protocol.ErrorCodes.InternalError, message = tostring(convert_err) }) end
    end)
  end

  convert(1)
end

--- Get code actions for a Zotero entry.
---@param entry BibEntry|ZoteroEntry Citation entry for the action.
---@param params table LSP code action params.
---@param callback fun(actions: table[]|nil, err?: lsp.ResponseError) Receives actions or an LSP error.
function actions.for_entry(entry, params, callback)
  if not entry.zotkey then return callback({}) end

  local db_path = require("bib.backends.zotero").db_path()
  if not db_path then return callback({}) end

  local result, err = read_zotero(db_path, entry)
  if err ~= nil then return callback(nil, err) end
  if not result then return callback({}) end

  return append_notes(result.actions, result.notes, params, callback)
end

return actions
