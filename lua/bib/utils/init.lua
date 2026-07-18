---@type table
local u = {}

--- Prefer citekey over key for display
---@param entry table
---@return string
function u.display_key(entry) return entry.citekey or entry.key end

u.backends = require("bib.utils.backends")
u.lsp = require("bib.utils.lsp")

return u
