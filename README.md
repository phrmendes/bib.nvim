# bib.nvim

Bibliography management for Neovim via LSP. Provides completion, hover, go-to-definition, and code actions for citation keys in Markdown and LaTeX documents.

## Features

- **LSP server** — completion, hover, go-to-definition for `@citekey` references
- **Automatic backend dispatch** — `.bib` files via tree-sitter, Zotero via sqlite
- **Composite key conceal** — `@ABC123#citekey` → hides the ID, shows only the citekey
- **`:Bib search`** — fuzzy picker over the active backend (`zotero` for Zotero-only)
- **Code actions** — Open PDF and Get notes from Zotero for citations
- **Markdown + LaTeX** — YAML frontmatter, `\addbibresource`, `.bib.json`, `!TeX root`

## Installation

With [vim.pack](https://neovim.io/doc/user/usr_05.html#vim.pack) (Neovim 0.12+):

```lua
vim.pack.add({
    "https://github.com/phrmendes/bib.nvim",
    "https://github.com/kkharji/sqlite.lua",
})
```

Requires [pandoc](https://pandoc.org) and [sqlite.lua](https://github.com/kkharji/sqlite.lua). Zotero users also need [BetterBibTeX](https://github.com/retorquere/zotero-better-bibtex) for citation key generation. Tree-sitter parsers for `bibtex`, `latex`, `markdown`, `markdown_inline`, and `yaml` are provided via `devenv.nix`.

## Quick start

```lua
require("bib").setup({
    filetypes = { "markdown", "tex" },
    zotero = { database = "/path/to/zotero.sqlite" },
})
```

The Zotero database path is auto-detected from the default location if not specified.

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

## Commands

- `:Bib search` — search the current backend and open the reference
- `:Bib search zotero` — search Zotero only

## Code actions

Triggered on a citation line:

- **Open PDF** — opens the attached PDF in the system viewer
- **Get notes from Zotero** — inserts Zotero notes below the citation as plain text

## Dependencies

- [BetterBibTeX for Zotero](https://github.com/retorquere/zotero-better-bibtex) — citation key generation
- [pandoc](https://pandoc.org) — Zotero note extraction
- [sqlite.lua](https://github.com/kkharji/sqlite.lua) — Zotero database access

## Credits

Zotero note extraction inspired by [zotcite](https://github.com/jalvesaq/zotcite).

## License

Apache-2.0
