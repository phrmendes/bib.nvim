---@type table
local notes = {}

--- Extract text from HTML using pandoc
---@param html string
---@return string|nil
function notes.to_markdown(html)
	local obj = vim.system({ "pandoc", "-f", "html", "-t", "plain", "--wrap=none" }, { stdin = html, text = true }):wait(5000)
	if obj.code ~= 0 then return nil end
	return obj.stdout
end

return notes
