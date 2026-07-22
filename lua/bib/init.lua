local c = require("bib.constants")

---@type BibConfig
local defaults = {
	filetypes = c.DEFAULT_FILETYPES,
	zotero = {},
}

---@type table
local bib = {}

--- Setup bib.nvim
---@param opts? BibConfig
function bib.setup(opts)
	bib.options = vim.tbl_deep_extend("force", defaults, opts or {})

	vim.lsp.config("bib_ls", {
		cmd = require("bib.lsp").server,
		filetypes = bib.options.filetypes,
	})

	require("bib.lsp").attach()

	vim.lsp.enable("bib_ls")

	vim.api.nvim_create_user_command("Bib", function(args)
		local parts = vim.split(args.args, " ", { trimempty = true })
		if #parts == 0 then return end
		require("bib.commands").search(parts[2])
	end, {
		nargs = "*",
		complete = function(arglead, cmdline)
			if not cmdline:find("Bib%s+search") then return vim.startswith("search", arglead) and { "search" } or {} end
			return vim.startswith("zotero", arglead) and { "zotero" } or {}
		end,
		desc = "Search bibliography entries",
	})
end

--- Get current config
---@return BibConfig
function bib.get() return bib.options end

return bib
