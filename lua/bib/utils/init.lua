---@type table
local u = {}

--- Strip surrounding braces or quotes from a value
---@param value string
---@return string
function u.strip_value(value)
	value = vim.trim(value)
	local pairs = { ["{"] = "}", ['"'] = '"' }
	local open = value:sub(1, 1)
	if pairs[open] == value:sub(-1, -1) then return value:sub(2, -2) end
	return value
end

--- Resolve a relative path against a base directory
---@param base string
---@param path string
---@return string|nil
function u.resolve_path(base, path)
	if not path or path == "" or path:sub(1, 1) == "/" or path:sub(2, 2) == ":" then return path end
	return vim.fn.fnamemodify(base .. "/" .. path, ":p")
end

--- Prefer citekey over key for display
---@param entry table
---@return string
function u.display_key(entry) return entry.citekey or entry.key end

u.backends = require("bib.utils.backends")
u.lsp = require("bib.utils.lsp")

return u
