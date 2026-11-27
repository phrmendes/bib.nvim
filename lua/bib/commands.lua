local format_item = require("bib.utils").format_item
local handle_selection = require("bib.utils").handle_selection
local load = require("bib.utils.backends").load

---@type table
local commands = {}

--- Search bib (or zotero) and open reference
---@param args? string Use `zotero` to restrict the search to Zotero.
function commands.search(args)
  local zotero_only = vim.trim(args or "") == "zotero"

  vim.schedule(function()
    local backend, err
    if zotero_only then
      backend, err = load.zotero()
    else
      backend, err = load.bib()
      if not backend then
        local fallback, fallback_err = load.zotero()
        backend = fallback
        if not fallback then err = err or fallback_err end
      end
    end

    if not backend and err ~= nil then vim.lsp.log.warn("[bib] search backend failed: " .. tostring(err)) end

    local raw = backend and backend:all()

    if not raw or #raw == 0 then
      vim.notify("No entries found", vim.log.levels.INFO)
      return
    end

    local items = vim.iter(raw):map(function(e) return { display = format_item(e), key = e.key, zotkey = e.zotkey } end):totable()

    vim.ui.select(items, {
      prompt = "References:",
      format_item = function(v) return v.display end,
    }, function(item) handle_selection(item, backend) end)
  end)
end

return commands
