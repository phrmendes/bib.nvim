# bib.nvim

bib.nvim provides citation completion, hover, definitions, and Zotero actions for Markdown and LaTeX.

## Installation

Install the plugin with [vim.pack](https://neovim.io/doc/user/usr_05.html#vim.pack) on Neovim 0.12 or newer:

```lua
vim.pack.add({ "https://github.com/phrmendes/bib.nvim" })
```

For Zotero, also install [sqlite.lua](https://github.com/kkharji/sqlite.lua):

```lua
vim.pack.add({ "https://github.com/kkharji/sqlite.lua" })
```

Install the Tree-sitter parsers for your features: `markdown` and `markdown_inline` for Markdown, `yaml` for frontmatter, `latex` for LaTeX, and `bibtex` for `.bib` files. Zotero note conversion also uses [pandoc](https://pandoc.org).

For Nix, add the plugin package from the flake:

```nix
inputs.bib.url = "github:phrmendes/bib.nvim";
# Add inputs.bib.packages.${pkgs.system}.bib-nvim to your Neovim plugins.
```

## Setup

```lua
require("bib").setup()
```

Run `:Bib` to select a reference. Run `:checkhealth bib` to check the installation.

For configuration, bibliography formats, and citation actions, see [`:help bib`](doc/bib.txt).

## License

Apache-2.0. See [LICENSE](LICENSE).
