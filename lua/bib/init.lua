--- *bib.nvim*
---
--- bib.nvim provides citation completion, hover, definitions, and code actions
--- for Markdown and LaTeX. It reads a `.bib` file or a Zotero database.
---
--- Setup ~
--- *bib-setup*
---
--- Call setup once at startup:
--- >lua
---   local err = require('bib').setup({
---     filetypes = { 'markdown', 'tex' },
---     zotero = { database = '/path/to/zotero.sqlite' },
---   })
---   if err then return end
--- <
--- Setup returns an error on failure.
--- Both options are optional:
--- - `filetypes`: filetypes that attach the LSP. The default is
---   `{ 'markdown', 'tex' }`.
--- - `zotero.database`: path to the Zotero SQLite database. The default is
---   `~/Zotero/zotero.sqlite`.
---
--- Requirements ~
--- *bib-requirements*
---
--- Neovim 0.12 or newer is required. Install the Tree-sitter parsers for the
--- features you use:
--- - `markdown` and `markdown_inline` for Markdown citations.
--- - `yaml` for a bibliography in Markdown frontmatter.
--- - `latex` for LaTeX citations and bibliography declarations.
--- - `bibtex` for `.bib` files.
---
--- Zotero requires `sqlite.lua`. bib.nvim reads the `citationKey` field when
--- available. Otherwise it uses the Zotero item key. `pandoc` converts Zotero
--- notes to plain text. Without pandoc, the inserted notes retain their HTML.
---
--- Bibliography selection ~
--- *bib-bibliography*
---
--- For Markdown, add an unquoted `bibliography` field to the frontmatter:
--- >text
---   ---
---   bibliography: refs.bib
---   ---
---
---   See @smith2020.
--- <
--- The path is relative to the document. For a LaTeX bibliography, use:
--- >text
---   \bibliography{refs}
--- <
--- For biblatex, use:
--- >text
---   \addbibresource{refs.bib}
--- <
--- Cite an entry with `\cite{smith2020}`.
--- A `% !TeX root = root.tex` comment selects the root document. bib.nvim
--- resolves its bibliography relative to that document.
---
--- A `.bib.json` file in the document directory or an ancestor also selects a
--- bibliography. Its path is relative to the `.bib.json` file:
--- >text
---   { "bibliography": "refs.bib" }
--- <
--- A document declaration takes priority over `.bib.json`. When neither exists,
--- bib.nvim looks for `references.bib` beside the document. It uses one
--- bibliography per document.
---
--- If the `.bib` file has no entries, bib.nvim tries Zotero. Zotero reads a
--- temporary SQLite snapshot, including committed WAL data. Saving a `.bib`
--- file in Neovim refreshes its attached documents. After an external edit,
--- save the document to reload its backend.
---
--- Commands ~
--- *bib-commands*
---
--- - `:Bib` and `:Bib search` select a reference from the current backend.
--- - `:Bib search zotero` selects a reference from Zotero only.
---
--- The picker uses `vim.ui.select`. Fuzzy selection depends on your UI
--- implementation. A `.bib` selection opens its definition. A Zotero
--- selection opens the item in Zotero.
---
--- Citation actions ~
--- *bib-actions*
---
--- Use Neovim's LSP functions on a citation. For example:
--- >lua
---   vim.lsp.buf.hover()
---   vim.lsp.buf.definition()
---   vim.lsp.buf.code_action()
--- <
--- Zotero citations can offer these code actions:
--- - `Open PDF`: open the first PDF attachment with the system handler.
--- - `Get notes from Zotero`: insert the item's notes below the citation.
---
--- Zotero completion uses a composite key such as `@ABC123#smith2020`.
--- Conceal hides the item key in Markdown, so the citation displays as
--- `@smith2020`. The full key remains in the file.
---
--- Troubleshooting ~
--- *bib-troubleshooting*
---
--- Run `:checkhealth bib` to check Neovim, the parsers, and the optional Zotero
--- dependencies. If no backend loads, find the Neovim LSP log with
--- `:lua print(vim.lsp.log.get_filename())`.
---
--- Apache License 2.0 Copyright (c) 2024 Pedro Mendes
---
---@tag bib
---@tag :Bib

local c = require("bib.constants")
local patterns = require("bib.patterns")

---@private
---@type BibConfig
local defaults = {
  filetypes = c.DEFAULT_FILETYPES,
  zotero = {},
}

local bib = {}

--- Configure and enable bib.nvim.
---
--- See |bib-setup| for the options and their defaults.
---
---@param opts? BibConfig Options that override the defaults.
---@return string|nil error Setup error, or nil on success.
function bib.setup(opts)
  local ok, setup_err = pcall(function()
    bib.options = vim.tbl_deep_extend("force", defaults, opts or {})

    vim.lsp.config("bib_ls", {
      cmd = require("bib.lsp").server,
      filetypes = bib.options.filetypes,
    })

    require("bib.lsp").attach()

    vim.lsp.enable("bib_ls")

    require("bib.conceal").enable(bib.options.filetypes)

    vim.api.nvim_create_user_command("Bib", function(args)
      local parts = vim.split(args.args, " ", { trimempty = true })
      local sub = parts[1] or "search"

      if sub ~= "search" then
        vim.notify("Bib: unknown subcommand: " .. sub, vim.log.levels.ERROR)
        return
      end

      local scope = parts[2]

      if scope and scope ~= "zotero" then
        vim.notify("Bib: unknown search scope: " .. scope, vim.log.levels.ERROR)
        return
      end

      require("bib.commands").search(scope)
    end, {
      nargs = "*",
      complete = function(arglead, cmdline)
        if not cmdline:find(patterns.bib_search) then return vim.startswith("search", arglead) and { "search" } or {} end

        return vim.startswith("zotero", arglead) and { "zotero" } or {}
      end,
      desc = "Search bibliography entries",
    })
  end)
  if not ok then return tostring(setup_err) end
end

--- Return the configuration, or nil before setup.
---@return BibConfig|nil config Configuration, or nil before setup.
function bib.get() return bib.options end

return bib
