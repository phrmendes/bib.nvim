local c = require("bib.constants")

---@type BibConfig
local defaults = {
	filetypes = c.DEFAULT_FILETYPES,
	zotero = {},
}

---@type table
local config = {}

--- Setup bib.nvim
---@param opts? BibConfig
function config.setup(opts)
	config.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

	vim.lsp.config("bib_ls", {
		cmd = function() return require("bib.lsp").server() end,
	})

	vim.api.nvim_create_autocmd("FileType", {
		pattern = config.options.filetypes,
		group = vim.api.nvim_create_augroup("BibPlugin", { clear = true }),
		callback = function(args) require("bib.lsp").start(args.buf) end,
	})

	vim.api.nvim_create_user_command("Bib", function(args)
		local parts = vim.split(args.args, " ", { trimempty = true })
		if #parts == 0 then return end
		local ns = parts[1]
		local rest = table.concat(parts, " ", 2)
		local cmd = require("bib.commands")

		if ns == "search" then cmd.search(rest) end
	end, {
		nargs = "*",
		complete = function(_, line)
			if #vim.split(line, " ") <= 2 then return { "search" } end
			return {}
		end,
		desc = "bib.nvim commands",
	})
end

--- Get current config
---@return BibConfig
function config.get() return config.options end

return config
