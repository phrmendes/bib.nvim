local test = require("mini.test")
local u = dofile("tests/utils.lua")
local eq = test.expect.equality

local child, T = u.new_child_set()

local entry = "@article{smith2020,\n  author = {John Smith},\n  title = {Test},\n  year = {2020}\n}"
local both = entry .. "\n" .. "@book{jones2021,\n  author = {Jane Jones},\n  title = {Book},\n  year = {2021}\n}"

T["setup"] = test.new_set()

T["setup"]["returns command setup errors without throwing"] = function()
  local result = child.lua([[
    local create = vim.api.nvim_create_user_command
    vim.api.nvim_create_user_command = function() error("command setup failed") end
    local ok, err = pcall(require("bib").setup, {})
    vim.api.nvim_create_user_command = create
    return { ok = ok, err = err or vim.NIL }
  ]])

  eq(result.ok, true)
  eq(type(result.err), "string")
  eq(result.err:find("command setup failed", 1, true) ~= nil, true)
end

T["setup"]["reports a missing bibliography query through the command"] = function()
  local dir = u.temp_dir()
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, vim.fs.joinpath(dir, "refs.bib"), entry)
  u.write_file(child, md, "---\nbibliography: refs.bib\n---\n")
  local result = child.lua(string.format(
    [[
      local lookup = vim.api.nvim_get_runtime_file
      vim.api.nvim_get_runtime_file = function(path, ...)
        if path == "queries/bibtex/strings.scm" then return {} end
        return lookup(path, ...)
      end
      local messages, warnings = {}, {}
      vim.notify = function(message) table.insert(messages, message) end
      vim.lsp.log.warn = function(message) table.insert(warnings, message) end
      require("bib").setup({ zotero = { database = %q } })
      vim.cmd.edit(%q)
      vim.cmd("Bib")
      assert(vim.wait(3000, function()
        return vim.iter(messages):any(function(message) return message == "No entries found" end)
      end))
      vim.api.nvim_get_runtime_file = lookup
      return { messages = messages, warnings = warnings }
    ]],
    vim.fs.joinpath(dir, "missing.sqlite"),
    md
  ))

  eq(vim.list_contains(result.messages, "No entries found"), true)
  eq(vim.iter(result.warnings):any(function(message) return message:find("query not found", 1, true) ~= nil end), true)
end

T["setup"]["reports runtime query lookup errors through the command"] = function()
  local dir = u.temp_dir()
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, vim.fs.joinpath(dir, "refs.bib"), entry)
  u.write_file(child, md, "---\nbibliography: refs.bib\n---\n")
  local result = child.lua(string.format(
    [[
      local lookup = vim.api.nvim_get_runtime_file
      vim.api.nvim_get_runtime_file = function(path, ...)
        if path == "queries/bibtex/strings.scm" then error("lookup failed") end
        return lookup(path, ...)
      end
      local messages, warnings = {}, {}
      vim.notify = function(message) table.insert(messages, message) end
      vim.lsp.log.warn = function(message) table.insert(warnings, message) end
      require("bib").setup({ zotero = { database = %q } })
      vim.cmd.edit(%q)
      vim.cmd("Bib")
      assert(vim.wait(3000, function() return vim.list_contains(messages, "No entries found") end))
      vim.api.nvim_get_runtime_file = lookup
      return { messages = messages, warnings = warnings }
    ]],
    vim.fs.joinpath(dir, "missing.sqlite"),
    md
  ))

  eq(vim.list_contains(result.messages, "No entries found"), true)
  eq(vim.iter(result.warnings):any(function(message) return message:find("lookup failed", 1, true) ~= nil end), true)
end

T["search"] = test.new_set()

T["search"]["the default command opens the reference picker"] = function()
  local dir = u.temp_dir()
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, vim.fs.joinpath(dir, "refs.bib"), entry)
  u.write_file(child, md, "---\nbibliography: refs.bib\n---\n")
  child.lua(string.format([[vim.cmd.edit(%q)]], md))
  child.lua(string.format(
    [[
      require("bib").setup({ zotero = { database = %q } })
      vim.ui.select = function(items) _G.default_items = items end
      vim.notify = function() end
      vim.cmd("Bib")
      assert(vim.wait(3000, function() return _G.default_items ~= nil end))
    ]],
    vim.fs.joinpath(dir, "missing.sqlite")
  ))

  eq(child.lua_get("_G.default_items and #_G.default_items or 0"), 1)
end

T["search"]["unknown subcommands report an error"] = function()
  local dir = u.temp_dir()
  local message = child.lua(string.format(
    [[
      require("bib").setup({ zotero = { database = %q } })
      local message
      vim.notify = function(value) message = value end
      vim.cmd("Bib unknown")
      return message
    ]],
    vim.fs.joinpath(dir, "missing.sqlite")
  ))

  eq(message, "Bib: unknown subcommand: unknown")
end

T["search"]["shows bib entries in picker"] = function()
  local dir = u.temp_dir()
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir, "missing.sqlite")))
  u.write_file(child, vim.fs.joinpath(dir, "refs.bib"), both)
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, md, "---\nbibliography: refs.bib\n---\n")
  child.lua(string.format("vim.cmd.edit(%q)", md))

  child.lua([[
    _G._sel_items = nil
    vim.ui.select = function(items, opts, on_choice) _G._sel_items = items end
  ]])

  child.lua("vim.cmd('Bib')")
  child.lua("vim.wait(1000, function() return _G._sel_items ~= nil end)")

  local items = child.lua_get("_G._sel_items")

  eq(#items, 2)

  local has_test = vim.iter(items):find(function(i) return i.display:find("Test") ~= nil end) ~= nil

  eq(has_test, true)

  local has_book = vim.iter(items):find(function(i) return i.display:find("Book") ~= nil end) ~= nil

  eq(has_book, true)
end

T["search"]["shows zotero entries in picker"] = function()
  local dir = u.temp_dir()
  u.setup_zotero_db(child, dir)
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, md, "# Hello")
  child.lua(string.format("vim.cmd.edit(%q)", md))
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir, "zotero.sqlite")))

  child.lua([[
    _G._sel_items = nil
    vim.ui.select = function(items, opts, on_choice) _G._sel_items = items end
  ]])

  child.lua("vim.cmd('Bib search zotero')")
  child.lua("vim.wait(1000, function() return _G._sel_items ~= nil end)")

  local items = child.lua_get("_G._sel_items")

  eq(#items, 1)

  local _, title = items[1].display:match("^(.+) %- (.+)$")

  eq(title, "Test Title")
end

T["search"]["format is author - title (year)"] = function()
  local dir = u.temp_dir()
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir, "missing.sqlite")))
  u.write_file(child, vim.fs.joinpath(dir, "refs.bib"), entry)
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, md, "---\nbibliography: refs.bib\n---\n")
  child.lua(string.format("vim.cmd.edit(%q)", md))

  child.lua([[
    _G._sel_items = nil
    vim.ui.select = function(items, opts, on_choice) _G._sel_items = items end
  ]])

  child.lua("vim.cmd('Bib')")
  child.lua("vim.wait(1000, function() return _G._sel_items ~= nil end)")

  local items = child.lua_get("_G._sel_items")
  local author_year, title = items[1].display:match("^(.+) %- (.+)$")

  eq(author_year, "Smith (2020)")
  eq(title, "Test")
end

T["search"]["formats multiple authors in the picker"] = function()
  local dir = u.temp_dir()
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, vim.fs.joinpath(dir, "refs.bib"), "@article{key, author = {Alice Smith, Bob Jones, Carol Brown}, title = {Paper}}")
  u.write_file(child, md, "---\nbibliography: refs.bib\n---\n")
  local items = child.lua(string.format(
    [[
      require("bib").setup({ zotero = { database = %q } })
      vim.cmd.edit(%q)
      local items
      vim.ui.select = function(value) items = value end
      vim.cmd("Bib")
      assert(vim.wait(3000, function() return items ~= nil end))
      return items
    ]],
    vim.fs.joinpath(dir, "missing.sqlite"),
    md
  ))

  eq(#items, 1)
  eq(items[1].display, "Smith et al - Paper")
end

T["search"]["cancelling the picker leaves the document open"] = function()
  local dir = u.temp_dir()
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, vim.fs.joinpath(dir, "refs.bib"), entry)
  u.write_file(child, md, "---\nbibliography: refs.bib\n---\n")
  local result = child.lua(string.format(
    [[
      require("bib").setup({ zotero = { database = %q } })
      vim.cmd.edit(%q)
      local selected = false
      vim.ui.select = function(_, _, choose)
        selected = true
        choose(nil)
      end
      vim.cmd("Bib")
      assert(vim.wait(3000, function() return selected end))
      return vim.api.nvim_buf_get_name(0)
    ]],
    vim.fs.joinpath(dir, "missing.sqlite"),
    md
  ))

  eq(result, md)
end

T["search"]["selection opens zotero URI"] = function()
  local dir = u.temp_dir()
  u.setup_zotero_db(child, dir)
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, md, "# Hello")
  child.lua(string.format("vim.cmd.edit(%q)", md))
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir, "zotero.sqlite")))

  child.lua([[
    _G._opened = nil
    vim.ui.open = function(uri)
      _G._opened = uri
      return {}
    end
    vim.ui.select = function(items, opts, on_choice) on_choice(items[1]) end
  ]])

  child.lua("vim.cmd('Bib search zotero')")
  child.lua("vim.wait(1000, function() return _G._opened ~= nil end)")

  local uri = child.lua_get("_G._opened")

  eq(uri, "zotero://select/library/items/ABC123")
end

T["search"]["selection opens the bibliography at the entry"] = function()
  local dir = u.temp_dir()
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir, "missing.sqlite")))
  local bib_path = vim.fs.joinpath(dir, "refs.bib")
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, bib_path, "\n" .. entry)
  u.write_file(child, md, "---\nbibliography: refs.bib\n---\nSee @smith2020.\n")
  child.lua(string.format([[vim.cmd.edit(%q); vim.api.nvim_win_set_cursor(0, { 4, 5 })]], md))
  child.lua([[
    vim.ui.select = function(items, _, choose) choose(items[1]) end
    vim.cmd("Bib")
  ]])
  child.lua(string.format("vim.wait(1000, function() return vim.api.nvim_buf_get_name(0) == %q end)", bib_path))

  eq(child.api.nvim_buf_get_name(0), bib_path)
  eq(child.api.nvim_win_get_cursor(0)[1], 2)
end

T["search"]["overlapping pickers retain their bibliography"] = function()
  local first, second = u.temp_dir(), u.temp_dir()
  vim.iter({ first, second }):each(function(dir)
    u.write_file(child, vim.fs.joinpath(dir, "refs.bib"), entry)
    u.write_file(child, vim.fs.joinpath(dir, "paper.md"), "---\nbibliography: refs.bib\n---\n")
  end)

  child.lua(string.format(
    [[
      require("bib").setup({ zotero = { database = %q } })
      _G.pickers = {}
      vim.ui.select = function(items, _, choose) table.insert(_G.pickers, { items = items, choose = choose }) end
      vim.cmd.edit(%q)
      vim.cmd("Bib")
      assert(vim.wait(1000, function() return #_G.pickers == 1 end))
      vim.cmd.edit(%q)
      vim.cmd("Bib")
      assert(vim.wait(1000, function() return #_G.pickers == 2 end))
      _G.pickers[1].choose(_G.pickers[1].items[1])
      assert(vim.wait(1000, function() return vim.api.nvim_buf_get_name(0) == %q end))
    ]],
    vim.fs.joinpath(first, "missing.sqlite"),
    vim.fs.joinpath(first, "paper.md"),
    vim.fs.joinpath(second, "paper.md"),
    vim.fs.joinpath(first, "refs.bib")
  ))
  eq(child.api.nvim_buf_get_name(0), vim.fs.joinpath(first, "refs.bib"))
end

T["search"]["zotero-only search does not fall back to a bib file"] = function()
  local dir = u.temp_dir()
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, vim.fs.joinpath(dir, "refs.bib"), entry)
  u.write_file(child, md, "---\nbibliography: refs.bib\n---\n")
  local result = child.lua(string.format(
    [[
      vim.cmd.edit(%q)
      require("bib").setup({ zotero = { database = %q } })
      local selected, message = false, nil
      vim.ui.select = function() selected = true end
      vim.notify = function(text) message = text end
      vim.cmd("Bib search zotero")
      assert(vim.wait(1000, function() return selected or message ~= nil end))
      return { selected = selected, message = message }
    ]],
    md,
    vim.fs.joinpath(dir, "missing.sqlite")
  ))

  eq(result, { selected = false, message = "No entries found" })
end

T["search"]["unscoped search falls back to Zotero"] = function()
  local dir = u.temp_dir()
  local db = u.setup_zotero_db(child, dir)
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, md, "# No bibliography")
  local items = child.lua(string.format(
    [[
      vim.cmd.edit(%q)
      require("bib").setup({ zotero = { database = %q } })
      local items
      vim.ui.select = function(value) items = value end
      vim.cmd("Bib")
      assert(vim.wait(1000, function() return items ~= nil end))
      return items
    ]],
    md,
    db
  ))

  eq(#items, 1)
  eq(items[1].zotkey, "ABC123")
end

T["search"]["reports returned and thrown Zotero open errors"] = function()
  local dir = u.temp_dir()
  local db = u.setup_zotero_db(child, dir)
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, md, "# Zotero")
  local result = child.lua(string.format(
    [[
      vim.cmd.edit(%q)
      require("bib").setup({ zotero = { database = %q } })
      local messages, attempts = {}, 0
      vim.notify = function(message) table.insert(messages, message) end
      vim.ui.select = function(items, _, choose) choose(items[1]) end
      vim.ui.open = function()
        attempts = attempts + 1
        if attempts == 1 then return nil, "no handler" end
        if attempts == 2 then error("spawn failed") end
        return {}
      end
      vim.cmd("Bib search zotero")
      assert(vim.wait(3000, function() return attempts == 1 end))
      vim.cmd("Bib search zotero")
      assert(vim.wait(3000, function() return attempts == 2 end))
      vim.cmd("Bib search zotero")
      assert(vim.wait(3000, function() return attempts == 3 end))
      return messages
    ]],
    md,
    db
  ))

  eq(#result, 2)
  eq(result[1]:find("no handler", 1, true) ~= nil, true)
  eq(result[2]:find("spawn failed", 1, true) ~= nil, true)
end

return T
