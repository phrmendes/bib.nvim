local c = require("bib.constants")
local ns = vim.api.nvim_create_namespace("bib_conceal")
local patterns = require("bib.patterns")

---@type table
local conceal = {}

---@param bufnr integer
function conceal.setup(bufnr)
	if vim.api.nvim_get_option_value("buftype", { buf = bufnr }) ~= "" then return end

	vim.api.nvim_set_hl(0, "BibCitePrefix", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "BibCiteKey", { link = "@string.special", default = true })

	local win = vim.fn.bufwinid(bufnr)

	if win ~= -1 then vim.api.nvim_set_option_value("conceallevel", c.CONCEAL_LEVEL, { scope = "local", win = win }) end

	local function apply()
		vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

		vim.iter(ipairs(lines)):each(function(lnum, line)
			local pos = 1

			while true do
				local match_start, match_end = line:find(patterns.conceal_prefix, pos)

				if not match_start then break end

				---@type {start_col: integer, end_col: integer, conceal?: string, hl_group?: string}[]
				local extmarks = {
					{ start_col = match_start - 1, end_col = match_start, hl_group = "BibCitePrefix" },
					{ start_col = match_start, end_col = match_end, conceal = "" },
				}

				local rest_start, rest_end = line:find(patterns.citekey_rest, match_end + 1)

				if rest_start then table.insert(extmarks, { start_col = rest_start - 1, end_col = rest_end, hl_group = "BibCiteKey" }) end

				vim.iter(extmarks):each(function(m) vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, m.start_col, m) end)

				pos = match_end + 1
			end
		end)
	end

	vim.api.nvim_create_autocmd({ "BufWinEnter", "InsertLeave", "TextChanged", "BufWritePost" }, {
		buffer = bufnr,
		group = vim.api.nvim_create_augroup("BibConceal/" .. bufnr, { clear = true }),
		callback = apply,
	})
end

return conceal
