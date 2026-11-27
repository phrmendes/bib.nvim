---@type table
local notes = {}

--- Extract text from HTML using pandoc.
---@param html string Zotero note content in HTML.
---@param callback fun(text: string|nil) Receives converted text, or nil when conversion fails.
function notes.to_markdown(html, callback)
  local ok = pcall(vim.system, { "pandoc", "-f", "html", "-t", "plain", "--wrap=none" }, {
    stdin = html,
    text = true,
    timeout = 5000,
  }, vim.schedule_wrap(function(result) callback(result.code == 0 and result.stdout or nil) end))
  if not ok then callback(nil) end
end

return notes
