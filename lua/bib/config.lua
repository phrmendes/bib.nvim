---@class BibConfig
---@field filetypes string[] Filetypes to enable on

---@type BibConfig
local defaults = {
	filetypes = { "markdown", "tex" },
}

local config = {}

---@type BibConfig
config.options = vim.deepcopy(defaults)

--- Setup bib.nvim
---@param opts? BibConfig
function config.setup(opts)
	config.options = vim.tbl_deep_extend("force", defaults, opts or {})

	vim.lsp.config("bib_ls", { cmd = function()
		local lsp = require("bib.lsp")
		return lsp.server()
	end, filetypes = config.options.filetypes })

	vim.api.nvim_create_autocmd("FileType", {
		pattern = config.options.filetypes,
		group = vim.api.nvim_create_augroup("BibPlugin", { clear = true }),
		callback = function(args)
			require("bib.lsp").start(args.buf)
		end,
	})
end

--- Get current config
---@return BibConfig
function config.get() return config.options end

return config
