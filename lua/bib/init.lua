local bib = {}

--- Setup bib.nvim
---@param opts? table Options passed to config.setup
function bib.setup(opts) require("bib.config").setup(opts) end

return bib
