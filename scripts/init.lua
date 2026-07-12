-- Prevent the FileType autocmd in plugin/bib.lua from firing during tests
vim.g.did_bib_plugin = true

vim.opt.runtimepath:append(vim.uv.cwd())
package.path = vim.fs.joinpath(vim.uv.cwd(), "lua", "?.lua")
  .. ";"
  .. vim.fs.joinpath(vim.uv.cwd(), "lua", "?", "init.lua")
  .. ";"
  .. package.path

if #vim.api.nvim_list_uis() == 0 then
  local packages_path = "deps"
  local mini_path = vim.fs.joinpath(packages_path, "pack", "deps", "start", "mini.nvim")

  if not vim.uv.fs_stat(mini_path) then
    local mini_repo = "https://github.com/echasnovski/mini.nvim"
    local out = vim.system({ "git", "clone", "--filter=blob:none", mini_repo, mini_path }):wait()
    if out.code ~= 0 then
      os.exit(1)
    end
  else
    local out = vim.system({ "git", "-C", mini_path, "pull" }):wait()
    if out.code ~= 0 then
      os.exit(1)
    end
  end

  -- Compile tree-sitter parsers if not present
  local parser_dir = vim.fs.joinpath(packages_path, "parser")
  vim.fn.mkdir(parser_dir, "p")

  local parsers = {
    {
      name = "bibtex",
      repo = "https://github.com/latex-lsp/tree-sitter-bibtex",
      sources = { "src/parser.c" },
    },
    {
      name = "latex",
      repo = "https://github.com/tree-sitter/tree-sitter-latex",
      sources = { "src/parser.c", "src/scanner.c" },
    },
    {
      name = "markdown",
      repo = "https://github.com/tree-sitter/tree-sitter-markdown",
      sources = { "tree-sitter-markdown/src/parser.c", "tree-sitter-markdown/src/scanner.c" },
    },
    {
      name = "yaml",
      repo = "https://github.com/tree-sitter-grammars/tree-sitter-yaml",
      sources = { "src/parser.c", "src/scanner.c" },
    },
  }

  for _, p in ipairs(parsers) do
    local parser_so = vim.fs.joinpath(parser_dir, p.name .. ".so")
    if not vim.uv.fs_stat(parser_so) then
      local ts_dir = vim.fs.joinpath(packages_path, "tree-sitter-" .. p.name)
      if not vim.uv.fs_stat(ts_dir) then
        local out = vim.system({ "git", "clone", "--depth=1", p.repo, ts_dir }):wait()
        if out.code ~= 0 then
          vim.notify("bib.nvim: failed to clone " .. p.repo, vim.log.levels.WARN)
        end
      end
      local sources = {}
      for _, s in ipairs(p.sources) do
        table.insert(sources, vim.fs.joinpath(ts_dir, s))
      end
      local args = { "cc", "-shared", "-o", parser_so, "-fPIC" }
      vim.list_extend(args, sources)
      table.insert(args, "-I")
      table.insert(args, vim.fs.joinpath(ts_dir, "src"))
      if p.name == "markdown" then
        table.insert(args, "-I")
        table.insert(args, vim.fs.joinpath(ts_dir, "tree-sitter-markdown/src"))
      end
      local out = vim.system(args):wait()
      if out.code ~= 0 then
        vim.notify("bib.nvim: failed to compile " .. p.name .. " parser", vim.log.levels.WARN)
      end
    end
  end

  vim.opt.runtimepath:append(vim.fs.joinpath(vim.uv.cwd(), packages_path))
  for _, p in ipairs(parsers) do
    pcall(vim.treesitter.language.add, p.name)
  end

  require("mini.test").setup()
  require("mini.doc").setup()
end
