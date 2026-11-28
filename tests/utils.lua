---@diagnostic disable: param-type-mismatch
local test = require("mini.test")

local utils = {}
local temp_dirs = {}

--- Create a temporary directory for a test.
---@return string
utils.temp_dir = function()
  local dir = vim.fn.tempname()
  table.insert(temp_dirs, dir)
  vim.fn.mkdir(dir, "p")
  return dir
end

--- Create a child Neovim test set with cleanup hooks.
---@return MiniTest.child
---@return table
utils.new_child_set = function()
  local child = test.new_child_neovim()
  local T = test.new_set({
    hooks = {
      pre_case = function() child.restart({ "--noplugin", "-u", "scripts/init.lua" }) end,
      post_case = function()
        for _, dir in ipairs(temp_dirs) do
          vim.fn.delete(dir, "rf")
        end

        temp_dirs = {}
      end,
      post_once = function() child.stop() end,
    },
  })

  return child, T
end

--- Write a file from the child process.
---@param child MiniTest.child
---@param path string
---@param content string
utils.write_file = function(child, path, content)
  local lines = vim.iter(vim.split(content, "\n")):map(function(line) return string.format("%q", line) end):totable()
  child.lua(string.format("vim.fn.writefile({ %s }, %q)", table.concat(lines, ", "), path))
end

--- Create a populated Zotero DB fixture.
---@param child MiniTest.child
---@param dir string
---@return string
utils.setup_zotero_db = function(child, dir)
  local db_path = vim.fs.joinpath(dir, "zotero.sqlite")
  local pdf_path = vim.fs.joinpath(dir, "test.pdf")
  utils.write_file(child, pdf_path, "%PDF-1.4\n%%EOF")
  local sql = string.format(
    [[
      local sqlite = require("sqlite")
      local db = sqlite.new(%q)
      db:open()
      db:eval("CREATE TABLE itemTypes (itemTypeID INTEGER PRIMARY KEY, typeName TEXT)")
      db:eval("CREATE TABLE fields (fieldID INTEGER PRIMARY KEY, fieldName TEXT)")
      db:eval("CREATE TABLE itemDataValues (valueID INTEGER PRIMARY KEY, value TEXT UNIQUE)")
      db:eval("CREATE TABLE items (itemID INTEGER PRIMARY KEY, itemTypeID INT, key TEXT, libraryID INT DEFAULT 1)")
      db:eval("CREATE TABLE itemData (itemID INT, fieldID INT, valueID INT, PRIMARY KEY (itemID, fieldID))")
      db:eval("CREATE TABLE creators (creatorID INTEGER PRIMARY KEY, lastName TEXT, firstName TEXT, fieldMode INT DEFAULT 0)")
      db:eval("CREATE TABLE creatorTypes (creatorTypeID INTEGER PRIMARY KEY, creatorType TEXT)")
      db:eval("CREATE TABLE itemCreators (itemID INT, creatorID INT, creatorTypeID INT, orderIndex INT DEFAULT 0, PRIMARY KEY (itemID, creatorID, creatorTypeID, orderIndex))")
      db:eval("CREATE TABLE itemNotes (itemID INTEGER PRIMARY KEY, parentItemID INT, note TEXT, title TEXT)")
      db:eval("CREATE TABLE itemAttachments (itemID INTEGER PRIMARY KEY, parentItemID INT, path TEXT, contentType TEXT)")
      db:eval("CREATE TABLE deletedItems (itemID INTEGER PRIMARY KEY)")
      db:eval("INSERT INTO itemTypes VALUES (1, 'journalArticle')")
      db:eval("INSERT INTO fields VALUES (1, 'title'), (2, 'abstractNote'), (6, 'date'), (9, 'citationKey')")
      db:eval("INSERT INTO itemDataValues VALUES (1, 'Test Title'), (2, 'An abstract.'), (3, '2020'), (4, 'smith2020')")
      db:eval("INSERT INTO items VALUES (1, 1, 'ABC123', 1)")
      db:eval("INSERT INTO itemData VALUES (1, 1, 1), (1, 2, 2), (1, 6, 3), (1, 9, 4)")
      db:eval("INSERT INTO creators VALUES (1, 'Smith', 'John', 0)")
      db:eval("INSERT INTO creatorTypes VALUES (1, 'author')")
      db:eval("INSERT INTO itemCreators VALUES (1, 1, 1, 0)")
      db:eval("INSERT INTO itemNotes VALUES (1, 1, 'A note about stuff.', 'Note 1')")
      db:eval("INSERT INTO itemAttachments VALUES (1, 1, ?, 'application/pdf')", %q)
      db:eval("INSERT INTO itemDataValues VALUES (5, 'Trashed Title'), (6, 'trashed2020')")
      db:eval("INSERT INTO items VALUES (2, 1, 'DEF456', 1)")
      db:eval("INSERT INTO itemData VALUES (2, 1, 5), (2, 9, 6)")
      db:eval("INSERT INTO deletedItems VALUES (2)")
      db:close()
    ]],
    db_path,
    pdf_path
  )
  child.lua(sql)
  return db_path
end

--- Create an empty Zotero DB fixture.
---@param child MiniTest.child
---@param dir string
---@return string
utils.setup_zotero_db_empty = function(child, dir)
  local db_path = vim.fs.joinpath(dir, "zotero.sqlite")
  local sql = string.format(
    [[
      local sqlite = require("sqlite")
      local db = sqlite.new("%s")
      db:open()
      db:eval("CREATE TABLE items (itemID INTEGER PRIMARY KEY, itemTypeID INT, key TEXT)")
      db:eval("CREATE TABLE itemData (itemID INT, fieldID INT, valueID INT)")
      db:eval("CREATE TABLE creators (creatorID INTEGER PRIMARY KEY, lastName TEXT, firstName TEXT)")
      db:eval("CREATE TABLE creatorTypes (creatorTypeID INTEGER PRIMARY KEY, creatorType TEXT)")
      db:eval("CREATE TABLE itemCreators (itemID INT, creatorID INT, creatorTypeID INT)")
      db:close()
    ]],
    db_path
  )
  child.lua(sql)
  return db_path
end

--- Create a malformed Zotero DB fixture.
---@param child MiniTest.child
---@param dir string
---@return string
utils.setup_zotero_db_malformed = function(child, dir)
  local db_path = vim.fs.joinpath(dir, "zotero.sqlite")
  local sql = string.format(
    [[
      local sqlite = require("sqlite")
      local db = sqlite.new("%s")
      db:open()
      db:eval("CREATE TABLE foo (x)")
      db:close()
    ]],
    db_path
  )
  child.lua(sql)
  return db_path
end

--- Send a bibliography LSP request.
---@param child MiniTest.child
---@param method string
---@param position {line: integer, character: integer}
---@return {err: any, result: any, calls: integer}
function utils.lsp_request(child, method, position)
  return child.lua(
    [[
      local method, position = ...
      local bufnr = vim.api.nvim_get_current_buf()
      local client
      assert(
        vim.wait(3000, function()
          client = vim.lsp.get_clients({ bufnr = bufnr, name = "bib_ls" })[1]
          return client ~= nil and client.initialized
        end),
        "bibliography LSP client did not attach"
      )
      local params = { textDocument = { uri = vim.uri_from_bufnr(bufnr) }, position = position }
      if method == "textDocument/codeAction" then
        params.position = nil
        params.range = { start = position, ["end"] = position }
        params.context = { diagnostics = {} }
      end
      local response, calls = nil, 0
      assert(client:request(method, params, function(err, result)
        calls = calls + 1
        response = { err = err or vim.NIL, result = result or vim.NIL }
      end, bufnr))
      assert(vim.wait(7000, function() return response ~= nil end), "bibliography LSP request timed out")
      response.calls = calls
      return response
    ]],
    { method, position }
  )
end

return utils
