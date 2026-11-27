local health = {}

--- Report whether a parser is available.
---@param name string Tree-sitter parser name.
---@param required boolean Report an error when true, or a warning when false.
---@param feature? string Feature that needs this optional parser.
---@private
local function check_parser(name, required, feature)
  local ok, loaded, err = pcall(vim.treesitter.language.add, name)
  if ok and loaded then
    vim.health.ok(name .. " parser available")
    return
  end

  local message = name .. " parser unavailable: " .. tostring(ok and err or loaded)
  if feature then message = message .. " (needed for " .. feature .. ")" end
  if required then
    vim.health.error(message)
    return
  end

  vim.health.warn(message)
end

--- Check the bib.nvim runtime requirements.
function health.check()
  vim.health.start("bib.nvim")

  if vim.fn.has("nvim-0.12") == 1 then
    vim.health.ok("Neovim 0.12 or newer")
  else
    vim.health.error("Neovim 0.12 or newer is required")
  end

  local bib = package.loaded.bib
  local config = bib and bib.get() or nil
  local filetypes = config and config.filetypes or require("bib.constants").DEFAULT_FILETYPES
  local markdown, tex = false, false
  for _, filetype in ipairs(filetypes) do
    if filetype == "tex" then
      tex = true
    else
      markdown = true
    end
  end

  if markdown then
    check_parser("markdown", true)
    check_parser("markdown_inline", true)
    check_parser("yaml", false, "Markdown frontmatter")
  end

  if tex then check_parser("latex", true) end
  check_parser("bibtex", false, ".bib files")

  local sqlite_ok = pcall(require, "sqlite")
  if sqlite_ok then
    vim.health.ok("sqlite.lua available for Zotero")
  else
    vim.health.warn("sqlite.lua unavailable; Zotero requires it")
  end

  if vim.fn.executable("pandoc") == 1 then
    vim.health.ok("pandoc available for Zotero notes")
  else
    vim.health.warn("pandoc unavailable; Zotero note conversion requires it")
  end

  local path = config and config.zotero and config.zotero.database or vim.fs.joinpath(vim.env.HOME or vim.fn.expand("~"), "Zotero", "zotero.sqlite")
  local stat = vim.uv.fs_stat(path)

  if stat and stat.type == "file" and vim.uv.fs_access(path, "R") then
    vim.health.ok("Zotero database available: " .. path)
  else
    vim.health.warn("Zotero database unavailable: " .. path .. " (needed for Zotero)")
  end
end

return health
