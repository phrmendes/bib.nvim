# bib.nvim Engineering Rules

## Architecture

- **Tree-sitter only.** No regex fallbacks for parsing. If tree-sitter doesn't provide the node, fix the query or walk the AST.
- **Markdown + tex filetypes only.** No typst, rnoweb, vimwiki, or other formats.
- **`.bib.json` is an equal method**, not a fallback. Same priority as YAML frontmatter and LaTeX commands.

## Backend protocol

Every backend implements these five functions:

```lua
load(bufnr)         → nil | throws error  # open the data source
match(prefix)       → BibEntry[]     # case-insensitive prefix match
get(key)            → BibEntry|nil   # single entry lookup
definition(key)     → {uri, range}   # LSP go-to location
hover(key)          → string|nil     # formatted hover content
```

## Style

- **Named modules.** No `M = {}` patterns. Return a named table directly.
- **No re-exports.** Every consumer imports the correct module directly. `require("bib.patterns")`, never `utils.patterns`.
- **Lookup tables over if/else chains.** Use `{[condition] = handler}` dictionaries.
- **vim.iter over manual loops.** Use `:map`, `:find`, `:fold`, `:each`. Plain `for` loops only when `vim.iter` would hurt readability (recursive tree walks use `:fold`).
- **No global variables.** No `vim.g.*` outside of config default access.
- **No section comments.** No `-- =====` or decorative separators.
- **Patterns in `bib.patterns`.** All regex lives in `lua/bib/patterns.lua` with `---@field` annotations. No raw regex strings in code.
- **No SQL in Lua code.** Queries go in `sql/` directory as named `.sql` files.
- **Helpers go to `bib.utils`.** No local functions unless the logic is specific to a single module and not reusable.

## Annotations

- `---@type` on every table: `---@type table<string, BibEntry>`
- `---@param` and `---@return` on every function
- `---@class` for named structured types
- Types go in `types.lua` when consumed by multiple modules (e.g., `bib/types.lua`, `bib/backends/types.lua`). Keep in-module otherwise.

## Diagnostics

- **No diagnostic disables.** Fix the root cause. Never suppress warnings with `---@diagnostic` or `---@type any`.

## Testing

- **TDD always.** RED → GREEN → REFACTOR. No code without a failing test.
- **Table-driven with vim.iter.** Use `vim.iter({cases}):each(...)`.
- **One test group per function under test.**
- **Child process isolation.** `tu.new_child_set()` for every test module. `--noplugin` on the child.
- **Clean temp dirs.** Temp directories cleaned in `post_case` hooks.

## Constraints

- **Bibtex only.** No biblatex support (`\addbibresource`).
- **No regex-based extraction.** Citation keys extracted via tree-sitter node text + character scanning from cursor position, not pattern matching.
- **Query files are lazy.** `lua/bib/queries.lua` uses metatable to load on first access (avoids crashing when optional parsers aren't available).

## Diff discipline

- **Baby steps.** Stop and ask if a diff exceeds ~300 lines.
- **Deletion over addition.** Prefer removing code over adding it.
- **Never patch symptoms.** Find the root cause, prove it with a failing test, then fix.

## Dependency rules

- **`sqlite.lua`** by kkharji — FFI to system `libsqlite3.so`.
- **No luarocks dependencies** — users install plugins alongside bib.nvim.
- **Devenv provides parsers** — `tree-sitter.withPlugins` in `devenv.nix`, registered via `vim.treesitter.language.add`.
