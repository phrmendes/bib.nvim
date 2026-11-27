local patterns = require("bib.patterns")
local find_bib_file = require("bib.utils.backends").find_bib_file
local parse = require("bib.utils.backends").parse

local DEFAULT_BIB = "references.bib"

local bib = {}

---@class BibBackend: Backend
---@field entries table<string, BibEntry>
local Backend = {}
Backend.__index = Backend

--- Resolve the .bib path for a buffer, with the default file as fallback.
---@param bufnr integer Buffer handle.
---@return string|nil path Resolved bibliography path, or nil on failure.
---@return string|nil error Resolution error, or nil on success.
---@private
local function resolve(bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local dir = bufname ~= "" and vim.fn.fnamemodify(bufname, ":p:h") or vim.fn.getcwd()

  local path, err = find_bib_file(bufnr)
  if err ~= nil then return nil, err end
  return path or vim.fn.fnamemodify(dir .. "/" .. DEFAULT_BIB, ":p")
end

--- Reload entries from the buffer's .bib file
---@param bufnr integer Buffer whose bibliography is reloaded.
---@return string|nil error Load error, or nil on success.
function Backend:load(bufnr)
  local resolved, path, err = pcall(resolve, bufnr)

  if not resolved then return tostring(path) end

  if path == nil then return err or "Could not resolve bibliography path" end

  local entries

  entries, err = parse(path)

  if err ~= nil then return err end

  self.path = path
  self.entries = entries or {}
end

--- Get entries whose key starts with a prefix (case-insensitive)
---@param prefix string Case-insensitive citation key prefix.
---@return BibEntry[] entries Matching entries.
function Backend:match(prefix)
  local lower = prefix:lower()
  return vim.iter(pairs(self.entries)):filter(function(key) return key:lower():find(lower, 1, true) == 1 end):map(function(_, entry) return entry end):totable()
end

--- Get a single entry by key
---@param key string Citation key.
---@return BibEntry|nil entry Matching entry, or nil if absent.
function Backend:get(key) return self.entries[key] end

--- Get all entries
---@return BibEntry[] entries All entries in the backend.
function Backend:all()
  return vim.iter(pairs(self.entries)):map(function(_, e) return e end):totable()
end

--- Search entries by substring (case-insensitive, matches key/title/author)
---@param query string Case-insensitive text to find.
---@return BibEntry[] entries Matching entries.
function Backend:search(query)
  local lower = query:lower()
  return vim
    .iter(pairs(self.entries))
    :filter(function(_, e)
      if e.key:lower():find(lower, 1, true) then return true end
      if e.fields.title and e.fields.title:lower():find(lower, 1, true) then return true end
      if e.fields.author and e.fields.author:lower():find(lower, 1, true) then return true end

      return false
    end)
    :map(function(_, e) return e end)
    :totable()
end

--- Get go-to-definition location for a key
---@param key string Citation key.
---@return {uri: string, range: table}|nil location Definition location, or nil if absent.
function Backend:definition(key)
  if not self.path then return end

  local entry = self.entries[key]
  if not entry then return end

  return {
    uri = vim.uri_from_fname(self.path),
    range = {
      start = { line = entry.line - 1, character = 0 },
      ["end"] = { line = entry.line - 1, character = 0 },
    },
  }
end

--- Get hover content for a key
---@param key string Citation key.
---@return string|nil text Markdown content, or nil if absent.
function Backend:hover(key)
  local entry = self.entries[key]
  if not entry then return end

  local header = {}
  if entry.fields.author then table.insert(header, entry.fields.author) end
  if entry.fields.title then table.insert(header, entry.fields.title) end
  if entry.fields.year then table.insert(header, entry.fields.year) end

  local parts = { "# " .. table.concat(header, " - ") }

  if entry.fields.abstract then
    local abstract = entry.fields.abstract:gsub(patterns.whitespace, " ")
    table.insert(parts, "---\n" .. abstract)
  end

  return table.concat(parts, "\n\n")
end

--- Load the .bib backend for a buffer.
--- Each call returns a new instance with its own entries.
---@param bufnr integer Buffer whose bibliography is loaded.
---@return Backend|nil backend Backend with its own entries, or nil on failure.
---@return string|nil error Load error, or nil on success.
function bib.load(bufnr)
  local backend = setmetatable({ entries = {} }, Backend)
  local err = backend:load(bufnr)
  if err ~= nil then return nil, err end
  return backend
end

return bib
