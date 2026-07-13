# bib.nvim

Bibliography management for Neovim via LSP. Provides completion, hover, and go-to-definition for citation keys in Markdown and LaTeX documents.

For full documentation, see [`:help bib.nvim`](doc/bib.txt).

## Installation

With [vim.pack](https://neovim.io/doc/user/usr_05.html#vim.pack) (Neovim 0.12+):

```lua
vim.pack.add({ "https://github.com/phrmendes/bib.nvim" })
```

## Quick start

Add a `bibliography` field to your Markdown frontmatter:

```markdown
---
bibliography: refs.bib
---

See @smith2020 for details.
```

Or use `\addbibresource` in LaTeX:

```latex
\documentclass{article}
\addbibresource{refs.bib}
\begin{document}
See \cite{smith2020}.
\end{document}
```

Or place a `.bib.json` file in the project root:

```json
{ "bibliography": "refs.bib" }
```

The LSP attaches automatically. Completion triggers on `@` (Markdown) or inside `\cite{}` (LaTeX).

## Configuration

```lua
require("bib").setup({
  filetypes = { "markdown", "tex" },
})
```

## License

Apache-2.0

## Roadmap

- [ ] Zotero integration: completion, hover, go-to-definition
  - Composite keys (`@id#citekey`)
  - sqlite.lua dependency
  - [ ] DB path auto-detection + config
  - [ ] `sql/queries.sql` named queries
  - [ ] `bib.backends.zotero` backend module
  - [ ] Auto-dispatch: .bib first, Zotero fallback
  - `:BibSearchZotero`: search full Zotero library, insert citation key
  - Notes: code action + :BibZoteroNotes command with vim.ui.select
  - PDF opening: code action opens in system viewer
