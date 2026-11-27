local test = require("mini.test")
local u = dofile("tests/utils.lua")
local eq = test.expect.equality

local child, T = u.new_child_set()

--- Open a document that cites a Zotero entry.
---@return {dir: string, db: string, document: string, position: {line: integer, character: integer}} fixture Real Zotero fixture and citation position.
local function open_zotero_citation()
  local dir = u.temp_dir()
  local db = u.setup_zotero_db(child, dir)
  local document = vim.fs.joinpath(dir, "paper.md")
  local position = { line = 2, character = 13 }
  u.write_file(child, document, "# Zotero\n\nSee @ABC123#smith2020.")
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } }); vim.cmd.edit(%q)", db, document))
  local hover = u.lsp_request(child, "textDocument/hover", position)
  eq(hover.err, vim.NIL)
  eq(hover.result.contents.value:find("Test Title", 1, true) ~= nil, true)
  return { dir = dir, db = db, document = document, position = position }
end

T["zotero_backend"] = test.new_set()

T["zotero_backend"]["reloads changed WAL data when file timestamps match"] = function()
  local dir = u.temp_dir()
  local db_path = u.setup_zotero_db(child, dir)
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, md, "# Zotero\n\nSee @ABC123#smith2020.")
  local result = child.lua(string.format(
    [[
    require('bib').setup({ zotero = { database = %q } })
    vim.cmd.edit(%q)
    local bufnr, client = vim.api.nvim_get_current_buf(), nil
    assert(vim.wait(3000, function()
      client = vim.lsp.get_clients({ bufnr = bufnr, name = 'bib_ls' })[1]
      return client and client.initialized
    end))
    local writer = require('sqlite').new(%q)
    writer:open()
    writer:eval('PRAGMA journal_mode=WAL')
    writer:eval('PRAGMA wal_autocheckpoint=0')
    local function reload(title)
      writer:eval("UPDATE itemDataValues SET value = ? WHERE valueID = 1", title)
      vim.iter({ '', '-wal', '-shm' }):each(function(suffix)
        local path = %q .. suffix
        if vim.uv.fs_stat(path) then assert(vim.uv.fs_utime(path, 1700000000, 1700000000)) end
      end)
      vim.cmd.write()
      local response = assert(client:request_sync('textDocument/hover', {
        textDocument = { uri = vim.uri_from_bufnr(bufnr) }, position = { line = 2, character = 13 },
      }, 3000, bufnr))
      assert(not response.err, response.err and response.err.message)
      return response.result.contents.value
    end
    local first = reload('First title')
    local second = reload('Second title')
    writer:close()
    return { first = first, second = second }
  ]],
    db_path,
    md,
    db_path,
    db_path
  ))

  eq(result.first:find("First title", 1, true) ~= nil, true)
  eq(result.second:find("Second title", 1, true) ~= nil, true)
end

T["zotero_backend"]["keeps citation data when the database is locked"] = function()
  local dir = u.temp_dir()
  local db_path = u.setup_zotero_db(child, dir)
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, md, "# Zotero\n\nSee @ABC123#smith2020.")
  local result = child.lua(string.format(
    [[
    require('bib').setup({ zotero = { database = %q } })
    vim.cmd.edit(%q)
    local bufnr, client = vim.api.nvim_get_current_buf(), nil
    assert(vim.wait(3000, function()
      client = vim.lsp.get_clients({ bufnr = bufnr, name = 'bib_ls' })[1]
      return client and client.initialized
    end))
    local writer = require('sqlite').new(%q)
    writer:open()
    writer:eval('PRAGMA journal_mode=DELETE')
    writer:eval('BEGIN EXCLUSIVE')
    local messages = {}
    vim.notify = function(message) table.insert(messages, message) end
    vim.cmd.write()
    writer:eval('ROLLBACK')
    writer:close()
    local response = assert(client:request_sync('textDocument/hover', {
      textDocument = { uri = vim.uri_from_bufnr(bufnr) }, position = { line = 2, character = 13 },
    }, 3000, bufnr))
    assert(not response.err, response.err and response.err.message)
    return { hover = response.result.contents.value, messages = messages }
  ]],
    db_path,
    md,
    db_path
  ))

  eq(result.hover:find("Test Title", 1, true) ~= nil, true)
  eq(#result.messages, 1)
  eq(result.messages[1]:find("backend reload failed", 1, true) ~= nil, true)
end

T["zotero_backend"]["removes its snapshot directory on exit"] = function()
  open_zotero_citation()
  local path = child.lua_get("require('bib.backends.zotero').db_path()")
  local dir = vim.fs.dirname(path)
  eq(vim.uv.fs_stat(path) ~= nil, true)

  child.stop()

  eq(vim.uv.fs_stat(dir), nil)
end

T["zotero_backend"]["excludes trashed items from completion"] = function()
  local dir = u.temp_dir()
  local db_path = u.setup_zotero_db(child, dir)
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, md, "# Zotero\n\nSee @tra\n\nSee @smi")
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } }); vim.cmd.edit(%q)", db_path, md))

  local trashed = u.lsp_request(child, "textDocument/completion", { line = 2, character = 7 })
  local active = u.lsp_request(child, "textDocument/completion", { line = 4, character = 7 })
  eq(trashed.err, vim.NIL)
  eq(#trashed.result.items, 0)
  eq(active.result.items[1].textEdit.newText, "ABC123#smith2020")
end

T["zotero_backend"]["excludes trashed attachments and notes from code actions"] = function()
  local dir = u.temp_dir()
  local db_path = u.setup_zotero_db(child, dir)
  local md = vim.fs.joinpath(dir, "paper.md")
  local pdf = vim.fs.joinpath(dir, "trashed.pdf")
  u.write_file(child, md, "# Zotero\n\nSee @ABC123#smith2020.")
  u.write_file(child, pdf, "%PDF-1.4\n%%EOF")
  child.lua(string.format(
    [[
    local db = require('sqlite').new(%q)
    db:open()
    db:eval('DELETE FROM itemAttachments')
    db:eval('DELETE FROM itemNotes')
    db:eval("INSERT INTO items VALUES (20, 1, 'ATTACH', 1), (21, 1, 'NOTE', 1)")
    db:eval("INSERT INTO itemAttachments VALUES (20, 1, ?, 'application/pdf')", %q)
    db:eval("INSERT INTO itemNotes VALUES (21, 1, 'A note', 'Note')")
    db:eval('INSERT INTO deletedItems VALUES (20), (21)')
    db:close()
    require('bib').setup({ zotero = { database = %q } })
    vim.cmd.edit(%q)
  ]],
    db_path,
    pdf,
    db_path,
    md
  ))

  local response = u.lsp_request(child, "textDocument/codeAction", { line = 2, character = 13 })
  eq(response.err, vim.NIL)
  eq(response.result, {})
end

T["zotero_backend"]["excludes a deleted parent from the picker"] = function()
  local dir = u.temp_dir()
  local db_path = u.setup_zotero_db(child, dir)
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, md, "# Zotero")
  local result = child.lua(string.format(
    [[
    local db = require('sqlite').new(%q)
    db:open()
    db:eval('INSERT INTO deletedItems VALUES (1)')
    db:close()
    local selected, messages = false, {}
    vim.ui.select = function() selected = true end
    vim.notify = function(message) table.insert(messages, message) end
    require('bib').setup({ zotero = { database = %q } })
    vim.cmd.edit(%q)
    vim.cmd('Bib search zotero')
    assert(vim.wait(3000, function() return selected or vim.list_contains(messages, 'No entries found') end))
    return { selected = selected, missing = vim.list_contains(messages, 'No entries found') }
  ]],
    db_path,
    db_path,
    md
  ))

  eq(result, { selected = false, missing = true })
end

T["zotero_backend"]["completes, locates, and describes a Zotero citation"] = function()
  local dir = u.temp_dir()
  local db_path = u.setup_zotero_db(child, dir)
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, md, "# Zotero\n\nSee @smi\nSee @ABC123#smith2020.")
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } }); vim.cmd.edit(%q)", db_path, md))

  local completion = u.lsp_request(child, "textDocument/completion", { line = 2, character = 7 })
  local hover = u.lsp_request(child, "textDocument/hover", { line = 3, character = 13 })
  local definition = u.lsp_request(child, "textDocument/definition", { line = 3, character = 13 })

  eq(#completion.result.items, 1)
  eq(completion.result.items[1].textEdit.newText, "ABC123#smith2020")
  eq(completion.result.items[1].label:find("smith2020", 1, true) ~= nil, true)
  eq(completion.result.items[1].label:find("ABC123", 1, true), nil)
  eq(hover.err, vim.NIL)
  eq(type(hover.result), "table")
  eq(hover.result.contents.value, "# John Smith - Test Title - 2020\n\n---\nAn abstract.")
  eq(definition.err, vim.NIL)
  eq(type(definition.result), "table")
  eq(definition.result.uri, "zotero://select/library/items/ABC123")
end

T["zotero_backend"]["uses the Zotero item key when the citation key is absent"] = function()
  local dir = u.temp_dir()
  local db_path = u.setup_zotero_db(child, dir)
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, md, "# Zotero\n\nSee @ABC")
  child.lua(string.format(
    [[
    local db = require('sqlite').new(%q)
    db:open()
    db:eval('DELETE FROM itemData WHERE itemID = 1 AND fieldID = 9')
    db:close()
    require('bib').setup({ zotero = { database = %q } })
    vim.cmd.edit(%q)
  ]],
    db_path,
    db_path,
    md
  ))

  local response = u.lsp_request(child, "textDocument/completion", { line = 2, character = 7 })
  eq(response.err, vim.NIL)
  eq(#response.result.items, 1)
  eq(response.result.items[1].textEdit.newText, "ABC123#ABC123")
  eq(response.result.items[1].label:find("ABC123", 1, true) ~= nil, true)
end

T["zotero_backend"]["uses the declared bibliography when Zotero is available"] = function()
  local dir = u.temp_dir()
  local db_path = u.setup_zotero_db(child, dir)
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, vim.fs.joinpath(dir, "refs.bib"), "@article{smith2020, title = {Bib Title}}")
  u.write_file(child, md, "---\nbibliography: refs.bib\n---\n\nSee @smith2020.")
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } }); vim.cmd.edit(%q)", db_path, md))

  local hover = u.lsp_request(child, "textDocument/hover", { line = 4, character = 8 })
  eq(hover.err, vim.NIL)
  eq(hover.result.contents.value, "# Bib Title")
end

T["zotero_failures"] = test.new_set()

T["zotero_failures"]["snapshot setup failure leaves no temporary directories"] = function()
  local dir = u.temp_dir()
  local db_path = u.setup_zotero_db(child, dir)
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, md, "# Zotero")
  local result = child.lua(string.format(
    [[
    require('bib').setup({ zotero = { database = %q } })
    local autocmd, mkdir = vim.api.nvim_create_autocmd, vim.uv.fs_mkdir
    local temporary, messages, warnings = {}, {}, {}
    vim.uv.fs_mkdir = function(path, mode)
      local result, err, code = mkdir(path, mode)
      if result then table.insert(temporary, path) end
      return result, err, code
    end
    vim.api.nvim_create_autocmd = function(events, opts)
      if events == 'VimLeavePre' then error('autocmd failure') end
      return autocmd(events, opts)
    end
    vim.notify = function(message) table.insert(messages, message) end
    vim.lsp.log.warn = function(message) table.insert(warnings, message) end
    vim.cmd.edit(%q)
    vim.cmd('Bib search zotero')
    assert(vim.wait(3000, function() return vim.list_contains(messages, 'No entries found') end))
    vim.api.nvim_create_autocmd, vim.uv.fs_mkdir = autocmd, mkdir
    return { count = #temporary, cleaned = vim.iter(temporary):all(function(path) return vim.uv.fs_stat(path) == nil end), warnings = warnings }
  ]],
    db_path,
    md
  ))

  eq(result.count > 0, true)
  eq(result.cleaned, true)
  eq(vim.iter(result.warnings):any(function(message) return message:find("autocmd failure", 1, true) ~= nil end), true)
end

T["zotero_failures"]["logs cleanup failures without replacing the primary error"] = function()
  local fixture = open_zotero_citation()
  local result = child.lua([[
    local unlink, rename = vim.uv.fs_unlink, vim.uv.fs_rename
    local count, temporary = 0, nil
    local messages, warnings = {}, {}
    vim.notify = function(message) table.insert(messages, message) end
    vim.lsp.log.warn = function(message) table.insert(warnings, message) end
    vim.uv.fs_unlink = function(path, ...)
      if path:sub(-4) == '.new' then
        count = count + 1
        temporary = path
        if count == 2 then return nil, 'cleanup permission denied', 'EACCES' end
      end
      return unlink(path, ...)
    end
    vim.uv.fs_rename = function() return nil, 'primary rename failure', 'EACCES' end
    vim.cmd.write()
    vim.uv.fs_unlink, vim.uv.fs_rename = unlink, rename
    if temporary then unlink(temporary) end
    return { messages = messages, warnings = warnings }
  ]])
  local hover = u.lsp_request(child, "textDocument/hover", fixture.position)

  eq(hover.result.contents.value:find("Test Title", 1, true) ~= nil, true)
  eq(#result.messages, 1)
  eq(result.messages[1]:find("primary rename failure", 1, true) ~= nil, true)
  eq(#result.warnings, 1)
  eq(result.warnings[1]:find("cleanup permission denied", 1, true) ~= nil, true)
end

T["zotero_failures"]["temporary cleanup failure preserves visible citation data"] = function()
  local fixture = open_zotero_citation()
  local messages = child.lua([[
    local unlink = vim.uv.fs_unlink
    vim.uv.fs_unlink = function(path, ...)
      if path:sub(-4) == '.new' then return nil, 'permission denied', 'EACCES' end
      return unlink(path, ...)
    end
    local messages = {}
    vim.notify = function(message) table.insert(messages, message) end
    vim.cmd.write()
    vim.uv.fs_unlink = unlink
    return messages
  ]])
  local hover = u.lsp_request(child, "textDocument/hover", fixture.position)

  eq(hover.result.contents.value:find("Test Title", 1, true) ~= nil, true)
  eq(#messages, 1)
  eq(messages[1]:find("permission denied", 1, true) ~= nil, true)
end

T["zotero_failures"]["database stat errors preserve visible citation data"] = function()
  local fixture = open_zotero_citation()
  local messages = child.lua(string.format(
    [[
    local stat = vim.uv.fs_stat
    vim.uv.fs_stat = function(path, ...)
      if path == %q then return nil, 'stat blocked', 'EACCES' end
      return stat(path, ...)
    end
    local messages = {}
    vim.notify = function(message) table.insert(messages, message) end
    vim.cmd.write()
    vim.uv.fs_stat = stat
    return messages
  ]],
    fixture.db
  ))
  local hover = u.lsp_request(child, "textDocument/hover", fixture.position)

  eq(hover.result.contents.value:find("Test Title", 1, true) ~= nil, true)
  eq(#messages, 1)
  eq(messages[1]:find("stat blocked", 1, true) ~= nil, true)
end

T["zotero_failures"]["query failure closes the snapshot and preserves citation data"] = function()
  local fixture = open_zotero_citation()
  local result = child.lua(string.format(
    [[
    local sqlite = require('sqlite')
    local writer = sqlite.new(%q)
    writer:open()
    writer:eval("UPDATE itemDataValues SET value = 'Changed' WHERE valueID = 1")
    writer:close()
    local original, count, closed = package.loaded.sqlite, 0, false
    package.loaded.sqlite = { new = function(...)
      count = count + 1
      local db = sqlite.new(...)
      if count == 3 then
        local close = db.close
        db.eval = function() error('query failure') end
        db.close = function(self, ...) closed = true; return close(self, ...) end
      end
      return db
    end }
    local messages = {}
    vim.notify = function(message) table.insert(messages, message) end
    vim.cmd.write()
    package.loaded.sqlite = original
    return { closed = closed, messages = messages }
  ]],
    fixture.db
  ))
  local hover = u.lsp_request(child, "textDocument/hover", fixture.position)

  eq(result.closed, true)
  eq(#result.messages, 1)
  eq(result.messages[1]:find("query failure", 1, true) ~= nil, true)
  eq(hover.result.contents.value:find("Test Title", 1, true) ~= nil, true)
end

vim.iter({ "missing", "empty", "malformed" }):each(function(kind)
  T["zotero_failures"][kind .. " database reports no entries through the command"] = function()
    local dir = u.temp_dir()
    local db = vim.fs.joinpath(dir, "zotero.sqlite")
    if kind == "empty" then db = u.setup_zotero_db_empty(child, dir) end
    if kind == "malformed" then db = u.setup_zotero_db_malformed(child, dir) end
    local md = vim.fs.joinpath(dir, "paper.md")
    u.write_file(child, md, "# Zotero")
    local result = child.lua(string.format(
      [[
      local selected, messages, warnings = false, {}, {}
      vim.ui.select = function() selected = true end
      vim.notify = function(message) table.insert(messages, message) end
      vim.lsp.log.warn = function(message) table.insert(warnings, message) end
      require('bib').setup({ zotero = { database = %q } })
      vim.cmd.edit(%q)
      vim.cmd('Bib search zotero')
      assert(vim.wait(3000, function() return selected or vim.list_contains(messages, 'No entries found') end))
      return { selected = selected, missing = vim.list_contains(messages, 'No entries found'), warnings = warnings }
    ]],
      db,
      md
    ))

    eq(result.selected, false)
    eq(result.missing, true)
    eq(vim.iter(result.warnings):any(function(message) return message:find("[bib] search backend failed:", 1, true) ~= nil end), true)
  end
end)

vim
  .iter({
    { name = "snapshot rename failure", failure = "rename", error = "injected rename failure" },
    { name = "invalid item data", failure = "item", error = "table index is nil" },
  })
  :each(function(case)
    T["zotero_failures"][case.name .. " preserves visible citation data"] = function()
      local fixture = open_zotero_citation()
      local result = child.lua(string.format(
        [[
      local writer = require('sqlite').new(%q)
      writer:open()
      writer:eval("UPDATE itemDataValues SET value = 'Changed' WHERE valueID = 1")
      if %q == 'item' then writer:eval('UPDATE fields SET fieldName = NULL WHERE fieldID = 1') end
      writer:close()
      local rename, unlink, temporary = vim.uv.fs_rename, vim.uv.fs_unlink, nil
      vim.uv.fs_unlink = function(path, ...)
        if path:sub(-4) == '.new' then temporary = path end
        return unlink(path, ...)
      end
      if %q == 'rename' then
        vim.uv.fs_rename = function(from, to)
          if from:sub(-4) == '.new' then return nil, 'injected rename failure', 'EACCES' end
          return rename(from, to)
        end
      end
      local messages = {}
      vim.notify = function(message) table.insert(messages, message) end
      vim.cmd.write()
      vim.uv.fs_rename, vim.uv.fs_unlink = rename, unlink
      return { messages = messages, temporary = temporary and vim.uv.fs_stat(temporary) ~= nil }
    ]],
        fixture.db,
        case.failure,
        case.failure
      ))
      local hover = u.lsp_request(child, "textDocument/hover", fixture.position)

      eq(hover.result.contents.value:find("Test Title", 1, true) ~= nil, true)
      eq(#result.messages, 1)
      eq(result.messages[1]:find(case.error, 1, true) ~= nil, true)
      eq(result.temporary, false)
    end
  end)

vim.iter({ { name = "source", index = 1 }, { name = "destination", index = 2 }, { name = "query snapshot", index = 3 } }):each(function(case)
  T["zotero_failures"][case.name .. " close failure preserves citation data"] = function()
    local fixture = open_zotero_citation()
    local result = child.lua(string.format(
      [[
      local sqlite = require('sqlite')
      local writer = sqlite.new(%q)
      writer:open()
      writer:eval("UPDATE itemDataValues SET value = 'Changed' WHERE valueID = 1")
      writer:close()
      local original, count, closed = package.loaded.sqlite, 0, {}
      package.loaded.sqlite = { new = function(...)
        count = count + 1
        local index = count
        local db = sqlite.new(...)
        local close = db.close
        db.close = function(self, ...)
          closed[index] = true
          local result = close(self, ...)
          if index == %d then error('injected close failure') end
          return result
        end
        return db
      end }
      local messages = {}
      vim.notify = function(message) table.insert(messages, message) end
      vim.cmd.write()
      package.loaded.sqlite = original
      return { messages = messages, source = closed[1] or false, destination = closed[2] or false }
    ]],
      fixture.db,
      case.index
    ))
    local hover = u.lsp_request(child, "textDocument/hover", fixture.position)

    eq(result.source, true)
    eq(result.destination, true)
    eq(#result.messages, 1)
    eq(result.messages[1]:find("injected close failure", 1, true) ~= nil, true)
    eq(hover.result.contents.value:find("Test Title", 1, true) ~= nil, true)
  end
end)

T["zotero_failures"]["backup finish error preserves visible citation data"] = function()
  local fixture = open_zotero_citation()
  local messages = child.lua([[
    local defs = require('sqlite.defs')
    local finish = defs.backup_finish
    defs.backup_finish = function(ptr) finish(ptr); return defs.flags.error end
    local messages = {}
    vim.notify = function(message) table.insert(messages, message) end
    vim.cmd.write()
    defs.backup_finish = finish
    return messages
  ]])
  local hover = u.lsp_request(child, "textDocument/hover", fixture.position)

  eq(#messages, 1)
  eq(messages[1]:find("SQLite backup failed", 1, true) ~= nil, true)
  eq(hover.result.contents.value:find("Test Title", 1, true) ~= nil, true)
end

T["zotero_failures"]["both database close failures preserve the primary error"] = function()
  local fixture = open_zotero_citation()
  local result = child.lua([[
    local sqlite = require('sqlite')
    local original, closed = package.loaded.sqlite, 0
    package.loaded.sqlite = { new = function(...)
      local db = sqlite.new(...)
      local close = db.close
      db.close = function(self, ...)
        closed = closed + 1
        close(self, ...)
        error('injected close failure ' .. closed)
      end
      return db
    end }
    local messages, warnings = {}, {}
    vim.notify = function(message) table.insert(messages, message) end
    vim.lsp.log.warn = function(message) table.insert(warnings, message) end
    vim.cmd.write()
    package.loaded.sqlite = original
    return { closed = closed, messages = messages, warnings = warnings }
  ]])
  local hover = u.lsp_request(child, "textDocument/hover", fixture.position)

  eq(result.closed, 2)
  eq(#result.messages, 1)
  eq(result.messages[1]:find("source close failed", 1, true) ~= nil, true)
  eq(#result.warnings, 1)
  eq(result.warnings[1]:find("destination close failed", 1, true) ~= nil, true)
  eq(hover.result.contents.value:find("Test Title", 1, true) ~= nil, true)
end
return T
