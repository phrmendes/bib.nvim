---@class BibZoteroConfig
---@field database? string Path to zotero.sqlite

---@class BibConfig
---@field filetypes string[] Filetypes to enable on
---@field zotero? BibZoteroConfig

---@class BibLspServer
---@field request fun(method: string, params: table, callback: BibLspCallback, _: table?)
---@field notify fun(method: string, _: table?)
---@field is_closing fun(): boolean
---@field terminate fun()

---@alias BibLspCallback fun(err: any, result: any)

---@class BibLspParams
---@field textDocument {uri: string}
---@field position {line: integer, character: integer}
---@field range? {start: {line: integer, character: integer}, ["end"]: {line: integer, character: integer}}

---@class BibLspCompletionItem : BibLspParams
---@field textEdit {newText: string}
---@field detail? string
---@field documentation? table
