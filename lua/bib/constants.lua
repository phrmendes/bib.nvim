---@type table
local constants = {}

---@type string[]
constants.DEFAULT_FILETYPES = { "markdown", "tex" }

--- Conceal level for hiding @ITEMID# prefix
---@type integer
constants.CONCEAL_LEVEL = 2

--- Max completion label length before truncation
---@type integer
constants.COMPLETION_MAX_LABEL = 80

return constants
