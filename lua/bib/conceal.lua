local c = require("bib.constants")
local collect_marks = require("bib.utils.conceal").collect_marks
local namespace = vim.api.nvim_create_namespace("bib_conceal")

---@type table
local conceal = {}

---@param bufnr integer
function conceal.setup(bufnr)
	if vim.api.nvim_get_option_value("buftype", { buf = bufnr }) ~= "" then return end

	vim.api.nvim_set_hl(0, "BibCitePrefix", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "BibCiteKey", { link = "@string.special", default = true })

	local win = vim.fn.bufwinid(bufnr)

	if win ~= -1 then vim.api.nvim_set_option_value("conceallevel", c.CONCEAL_LEVEL, { scope = "local", win = win }) end

	vim.api.nvim_create_autocmd({ "BufWinEnter", "InsertLeave", "TextChanged", "BufWritePost" }, {
		buffer = bufnr,
		group = vim.api.nvim_create_augroup("BibConceal" .. bufnr, { clear = true }),
		callback = function()
			vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)

			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			local skip = { fenced_code_block = true, code_fence_content = true, code_span = true }

			vim.iter(ipairs(lines)):each(function(lnum, line)
				local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { lnum - 1, 0 } })

				while node do
					if skip[node:type()] then return end
					node = node:parent()
				end

				vim.iter(collect_marks(line)):each(function(mark) vim.api.nvim_buf_set_extmark(bufnr, namespace, lnum - 1, mark.col, mark.opts) end)
			end)
		end,
	})
end

return conceal
