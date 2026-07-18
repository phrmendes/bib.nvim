---@class BibEntry
---@field key string The citation key
---@field type string The entry type (article, book, etc.)
---@field fields table<string, string> Field name -> value
---@field line integer Line number in the .bib file (1-indexed)

---@class ZoteroEntry
---@field key string Composite key (itemID#citekey)
---@field zotkey string Zotero item key
---@field citekey string Clean citation key (smith2020)
---@field type string Entry type (journalArticle, book, etc.)
---@field fields table<string, string> Field name -> value
---@field creators table<string, string> Creator type -> comma-separated names

---@class Backend
---@field load fun(bufnr: integer)
---@field match fun(prefix: string): BibEntry[] | ZoteroEntry[]
---@field get fun(key: string): BibEntry | ZoteroEntry | nil
---@field definition fun(key: string): {uri: string, range: table} | nil
---@field hover fun(key: string): string | nil
