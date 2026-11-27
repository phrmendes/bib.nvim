---@type table
local utils = {}
local p = require("bib.patterns")

--- Prefer citekey over key for display
---@param entry table Citation entry.
---@return string key Preferred citation key.
function utils.display_key(entry) return entry.citekey or entry.key end

--- Format entry for picker display: author - title
---@param e table Citation entry to display.
---@return string text Picker label.
function utils.format_item(e)
  local author = e.creators and e.creators.author or e.fields.author or "?"
  local authors = vim.split(author, ", ")
  local lastnames = vim.iter(authors):map(function(a) return a:match(p.lastname) or a end):totable()

  if #lastnames > 2 then
    author = lastnames[1] .. " et al"
  else
    author = table.concat(lastnames, ", ")
  end

  if e.fields.year then author = author .. " (" .. e.fields.year .. ")" end

  local title = e.fields.title or "Untitled"
  return string.format("%s - %s", author, title)
end

--- Open a path and report failures.
---@param path string Path or URI to open.
---@return string|nil error Open error, or nil on success.
function utils.open(path)
  local ok, process, err = pcall(vim.ui.open, path)
  if not ok or not process then
    local failure = tostring(ok and (err or "unknown error") or process)
    vim.notify("[bib] could not open " .. path .. ": " .. failure, vim.log.levels.ERROR)
    return failure
  end
end

--- Dispatch selected entry to the right action (zotero URI or LSP jump)
---@param item {display: string, key: string?, zotkey: string?}|nil Selected picker item, or nil on cancellation.
---@param backend Backend Backend that resolves bibliography entries.
---@return string|nil error Open error, or nil on success.
function utils.handle_selection(item, backend)
  if not item then return end

  if item.zotkey then return utils.open("zotero://select/library/items/" .. item.zotkey) end

  if item.key then
    local loc = backend:definition(item.key)
    if loc and loc.range then vim.lsp.util.show_document({ uri = loc.uri, range = loc.range }, "utf-8", { focus = true }) end
  end
end

return utils
