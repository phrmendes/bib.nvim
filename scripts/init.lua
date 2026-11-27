vim.g.did_bib_plugin = true

vim.opt.runtimepath:append(vim.uv.cwd())
package.path = vim.fs.joinpath(vim.uv.cwd(), "lua", "?.lua") .. ";" .. vim.fs.joinpath(vim.uv.cwd(), "lua", "?", "init.lua") .. ";" .. package.path

if #vim.api.nvim_list_uis() == 0 then
  local mini = assert(vim.env.MINI_NVIM, "MINI_NVIM is not set. Run this config through `devenv test`.")
  local sqlite = assert(vim.env.SQLITE_LUA, "SQLITE_LUA is not set. Run this config through devenv test.")
  vim.opt.runtimepath:append({ mini, sqlite })

  local grammars_dir = vim.env.BIB_GRAMMARS

  if grammars_dir then
    vim.iter({ "bibtex", "latex", "markdown", "markdown_inline", "yaml" }):each(function(name)
      local so = vim.fs.joinpath(grammars_dir, name .. ".so")
      if not vim.uv.fs_stat(so) then return end

      pcall(vim.treesitter.language.add, name, { path = so })
    end)
  end

  require("mini.test").setup()
  require("mini.doc").setup({
    hooks = {
      doc_pre = function(lines) return lines end,
    },
  })
end
