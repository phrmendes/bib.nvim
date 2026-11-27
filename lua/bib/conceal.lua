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
---@param bufnr integer Buffer handle.
---@param row integer 0-indexed row
---@param col integer 0-indexed column
---@param tree TSTree|nil Parsed host tree, or nil if unavailable.
---@return boolean inside True if the position is inside code.
---@private
local function in_code(bufnr, row, col, tree)
  return vim.iter(ipairs({ true, false })):any(function(_, ignore)
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr, pos = { row, col }, ignore_injections = ignore })
    if ignore and tree and (not ok or not node) then
      ok, node = pcall(function() return tree:root():named_descendant_for_range(row, col, row, col) end)
    end
    if not ok then return false end

    while node do
      if SKIP_TYPES[node:type()] then return true end

      node = node:parent()
    end

    return false
  end)
end

--- Update citation conceal marks for a buffer.
---@param bufnr integer Buffer handle.
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
      local tree
      if ok and parser then
        local trees = parser:parse()
        tree = trees and trees[1]
      end

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      vim.iter(ipairs(lines)):each(function(lnum, line)
        local code = inline_code_ranges(line)

        vim.iter(collect_marks(line)):each(function(mark)
          local col = mark.col + 1

          if vim.iter(ipairs(code)):any(function(_, span) return col >= span.s and col <= span.e end) then return end

          if in_code(bufnr, lnum - 1, mark.col, tree) then return end

          vim.api.nvim_buf_set_extmark(bufnr, namespace, lnum - 1, mark.col, mark.opts)
        end)
      end)
    end,
  })
end

--- Register FileType autocmd to apply conceal to configured filetypes
---@param filetypes string[] Filetypes that receive conceal marks.
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
