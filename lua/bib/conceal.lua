local c = require("bib.constants")
local conceal_utils = require("bib.utils.conceal")
local collect_marks = conceal_utils.collect_marks
local inline_code_ranges = conceal_utils.inline_code_ranges
local namespace = vim.api.nvim_create_namespace("bib_conceal")

---@type table
local conceal = {}

local SKIP_TYPES = { fenced_code_block = true, code_fence_content = true, code_span = true }

--- True when a position sits inside a fenced block or an inline code span.
--- `ignore_injections = false` is required: inline code lives in the
--- markdown_inline injection, and `get_node` skips injections by default.
---@param bufnr integer
---@param row integer 0-indexed row
---@param col integer 0-indexed column
---@return boolean
local function in_code(bufnr, row, col)
	for _, ignore in ipairs({ true, false }) do
		local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr, pos = { row, col }, ignore_injections = ignore })
		if ok then
			while node do
				if SKIP_TYPES[node:type()] then return true end
				node = node:parent()
			end
		end
	end
	return false
end

---@param bufnr integer
---@return nil
function conceal.setup(bufnr)
	if vim.api.nvim_get_option_value("buftype", { buf = bufnr }) ~= "" then return end

	vim.api.nvim_create_autocmd({ "BufWinEnter", "InsertLeave", "TextChanged", "BufWritePost" }, {
		buffer = bufnr,
		group = vim.api.nvim_create_augroup("BibConceal" .. bufnr, { clear = true }),
		callback = function(args)
			if args.event == "BufWinEnter" then vim.api.nvim_set_option_value("conceallevel", c.CONCEAL_LEVEL, { scope = "local" }) end

			vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
			local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
			if ok and parser then parser:parse() end

			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

			vim.iter(ipairs(lines)):each(function(lnum, line)
				local code = inline_code_ranges(line)

				vim.iter(collect_marks(line)):each(function(mark)
					local col = mark.col + 1
					for _, span in ipairs(code) do
						if col >= span.s and col <= span.e then return end
					end
					if in_code(bufnr, lnum - 1, mark.col) then return end
					vim.api.nvim_buf_set_extmark(bufnr, namespace, lnum - 1, mark.col, mark.opts)
				end)
			end)
		end,
	})
end

--- Register FileType autocmd to apply conceal to configured filetypes
---@param filetypes string[]
---@return nil
function conceal.enable(filetypes)
	vim.api.nvim_set_hl(0, "BibCitePrefix", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "BibCiteKey", { link = "@string.special", default = true })

	vim.api.nvim_create_autocmd("FileType", {
		pattern = filetypes,
		group = vim.api.nvim_create_augroup("BibConcealInit", { clear = true }),
		callback = function(args) conceal.setup(args.buf) end,
	})
end

return conceal
