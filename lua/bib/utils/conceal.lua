local p = require("bib.patterns")

---@type table
local conceal = {}

--- Byte ranges of inline code spans on a line. Backtick runs must match, so
--- ``a `b` c`` closes on the same single backtick. An unclosed run is ignored.
---@param line string Text line to inspect.
---@return { s: integer, e: integer }[] ranges 1-indexed start and end columns
function conceal.inline_code_ranges(line)
  local ranges = {}
  local init = 1

  while true do
    local s = line:find("`", init, true)
    if not s then break end

    local run = line:match("^`+", s)
    local e = line:find(run, s + #run, true)

    if not e then break end

    table.insert(ranges, { s = s, e = e + #run - 1 })
    init = e + #run
  end

  return ranges
end

--- Collect extmark specs from a line for @ITEMID#citekey (Zotero) and @citekey (bib) patterns
---@param line string Text line to inspect.
---@return table[] marks Array of {col: integer, opts: table} specs
function conceal.collect_marks(line)
  local boundary = "[%s%(%[{,;:'\"`<>]"

  return vim.iter(line:gmatch(p.conceal_scan)):fold({}, function(marks, pos, key)
    local before = pos > 1 and line:sub(pos - 1, pos - 1) or " "
    if not before:match(boundary) then return marks end

    local at_col = pos - 1
    local hash = key:find("#", 1, true)

    marks[#marks + 1] = { col = at_col, opts = { end_col = at_col + 1, hl_group = "BibCitePrefix" } }

    if hash then
      marks[#marks + 1] = { col = at_col + 1, opts = { end_col = at_col + hash + 1, conceal = "", hl_group = "BibCitePrefix" } }
      local citekey = key:sub(hash + 1)
      if citekey ~= "" then marks[#marks + 1] = { col = at_col + hash + 1, opts = { end_col = at_col + hash + 1 + #citekey, hl_group = "BibCiteKey" } } end
    else
      marks[#marks + 1] = { col = at_col + 1, opts = { end_col = at_col + 1 + #key, hl_group = "BibCiteKey" } }
    end

    return marks
  end)
end

return conceal
