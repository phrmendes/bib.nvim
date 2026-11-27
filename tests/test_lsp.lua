local test = require("mini.test")
local u = dofile("tests/utils.lua")
local eq = test.expect.equality

local child, T = u.new_child_set()

local entry = "@article{smith2020,\n  author = {John Smith},\n  title = {Test},\n  year = {2020}\n}"

local completion_kind = 18

--- Create a document and load its bibliography backend.
---@param md_content string
---@return string
local function setup_handler(md_content)
  local dir = u.temp_dir()
  u.write_file(child, vim.fs.joinpath(dir, "refs.bib"), entry)
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, md, md_content)
  child.lua(string.format("vim.cmd.edit(%q)", md))
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir, "missing.sqlite")))
  return dir
end

T["lsp_start"] = test.new_set()

vim
  .iter({
    { name = "attaches lsp client when bib found", content = entry, expected = true },
    { name = "stops client when no backend available", content = nil, expected = false },
  })
  :each(function(c)
    T["lsp_start"][c.name] = function()
      local dir = u.temp_dir()
      local md = vim.fs.joinpath(dir, "paper.md")
      if c.content then u.write_file(child, vim.fs.joinpath(dir, "refs.bib"), c.content) end
      u.write_file(child, md, c.content and "---\nbibliography: refs.bib\n---\nSee @smith2020." or "# No bib")
      local has = child.lua(string.format(
        [[
        vim.cmd.edit(%q)
        local attached = false
        vim.api.nvim_create_autocmd('LspAttach', { callback = function(args)
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          if client and client.name == 'bib_ls' then attached = true end
        end })
        require('bib').setup({ zotero = { database = %q } })
        assert(vim.wait(3000, function() return attached end))
        local expected = %s
        assert(vim.wait(3000, function()
          return (#vim.lsp.get_clients({ bufnr = 0, name = 'bib_ls' }) > 0) == expected
        end))
        return #vim.lsp.get_clients({ bufnr = 0, name = 'bib_ls' }) > 0
      ]],
        md,
        vim.fs.joinpath(dir, "missing.sqlite"),
        tostring(c.expected)
      ))

      eq(has, c.expected)
    end
  end)

T["lsp_handlers"] = test.new_set()

T["lsp_handlers"]["completion returns items matching prefix"] = function()
  setup_handler("---\nbibliography: refs.bib\n---\n\nSee @smi")
  local r = u.lsp_request(child, "textDocument/completion", { line = 4, character = 7 })

  eq(r.err, vim.NIL)
  eq(#r.result.items, 1)
  eq(r.result.items[1].textEdit.newText, "smith2020")
  eq(r.result.items[1].kind, completion_kind)
  eq(r.result.items[1].label:find("[article]", 1, true) ~= nil, true)
end

T["lsp_handlers"]["completion uses UTF-8 positions after non-ASCII text"] = function()
  setup_handler("---\nbibliography: refs.bib\n---\n\né @smi")
  local r = u.lsp_request(child, "textDocument/completion", { line = 4, character = 6 })

  eq(#r.result.items, 1)
  eq(r.result.items[1].textEdit.newText, "smith2020")
  eq(r.result.items[1].textEdit.range.start.character, 4)
end

T["lsp_handlers"]["completion uses the current line in a multi-line paragraph"] = function()
  local line = "é See @smi"
  setup_handler("---\nbibliography: refs.bib\n---\n\nEarlier text\n" .. line)
  local at = assert(line:find("@smi", 1, true))
  local response = u.lsp_request(child, "textDocument/completion", { line = 5, character = at + 2 })

  eq(response.err, vim.NIL)
  eq(#response.result.items, 1)
  eq(response.result.items[1].textEdit.newText, "smith2020")
  eq(response.result.items[1].textEdit.range.start.character, at)
end

T["lsp_handlers"]["completion returns empty when no key"] = function()
  setup_handler("---\nbibliography: refs.bib\n---\n\nSee no key here")
  local r = u.lsp_request(child, "textDocument/completion", { line = 4, character = 10 })

  eq(r.err, vim.NIL)
  eq(#r.result.items, 0)
end

T["lsp_handlers"]["initialize advertises utf-8 position encoding"] = function()
  setup_handler("---\nbibliography: refs.bib\n---\n\nSee @smith2020")
  local encoding = child.lua([[
    local client
    assert(vim.wait(3000, function()
      client = vim.lsp.get_clients({ bufnr = 0, name = 'bib_ls' })[1]
      return client and client.initialized
    end))
    return client.offset_encoding
  ]])

  eq(encoding, "utf-8")
end

T["lsp_handlers"]["definition returns bib file location"] = function()
  local dir = setup_handler("---\nbibliography: refs.bib\n---\n\nSee @smith2020")
  local r = u.lsp_request(child, "textDocument/definition", { line = 4, character = 12 })

  eq(r.err, vim.NIL)
  eq(r.result.uri, vim.uri_from_fname(vim.fs.joinpath(dir, "refs.bib")))
  eq(r.result.range.start.line, 0)
  eq(r.result.range.start.character, 0)
end

T["lsp_handlers"]["completes and locates citation keys with hyphens"] = function()
  local dir = u.temp_dir()
  local refs = vim.fs.joinpath(dir, "refs.bib")
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, refs, "@article{smith-jones-2020, title = {Hyphenated}}")
  u.write_file(child, md, "---\nbibliography: refs.bib\n---\n\nSee @smith-jones-2020")
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } }); vim.cmd.edit(%q)", vim.fs.joinpath(dir, "missing.sqlite"), md))

  local position = { line = 4, character = 13 }
  local completion = u.lsp_request(child, "textDocument/completion", position)
  local definition = u.lsp_request(child, "textDocument/definition", position)
  eq(completion.result.items[1].textEdit.newText, "smith-jones-2020")
  eq(definition.result.uri, vim.uri_from_fname(refs))
end

T["lsp_handlers"]["hover returns formatted content"] = function()
  setup_handler("---\nbibliography: refs.bib\n---\n\nSee @smith2020")
  local r = u.lsp_request(child, "textDocument/hover", { line = 4, character = 12 })

  eq(r.err, vim.NIL)
  local value = r.result.contents.value

  eq(value:find("John Smith") ~= nil, true)
  eq(value:find("Test") ~= nil, true)
  eq(value:find("2020") ~= nil, true)
end

T["lsp_handlers"]["hover includes a normalized bibliography abstract"] = function()
  local dir = u.temp_dir()
  local refs, md = vim.fs.joinpath(dir, "refs.bib"), vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, refs, "@article{test2020, author = {Jane Doe}, title = {With Abstract}, year = {2020}, abstract = {A test  abstract.}}")
  u.write_file(child, md, "---\nbibliography: refs.bib\n---\n\nSee @test2020.")
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } }); vim.cmd.edit(%q)", vim.fs.joinpath(dir, "missing.sqlite"), md))

  local response = u.lsp_request(child, "textDocument/hover", { line = 4, character = 8 })
  eq(response.err, vim.NIL)
  eq(response.result.contents.value, "# Jane Doe - With Abstract - 2020\n\n---\nA test abstract.")
end

T["lsp_handlers"]["completion returns empty inside code fence"] = function()
  setup_handler("---\nbibliography: refs.bib\n---\n\n```markdown\n@smi\n```\n\nSee @smi")
  local inside = u.lsp_request(child, "textDocument/completion", { line = 5, character = 3 })
  local outside = u.lsp_request(child, "textDocument/completion", { line = 8, character = 7 })

  eq(inside.err, vim.NIL)
  eq(#inside.result.items, 0)
  eq(outside.err, vim.NIL)
  eq(outside.result.items[1].textEdit.newText, "smith2020")
end

T["lsp_handlers"]["keeps separate backends per buffer"] = function()
  local dir_a = u.temp_dir()
  local dir_b = u.temp_dir()
  u.write_file(child, vim.fs.joinpath(dir_a, "a.bib"), "@article{commonAlpha, title = {Alpha}}")
  u.write_file(child, vim.fs.joinpath(dir_b, "b.bib"), "@article{commonBeta, title = {Beta}}")

  local md_a = vim.fs.joinpath(dir_a, "a.md")
  local md_b = vim.fs.joinpath(dir_b, "b.md")
  u.write_file(child, md_a, "---\nbibliography: a.bib\n---\n\nSee @com")
  u.write_file(child, md_b, "---\nbibliography: b.bib\n---\n\nSee @com")

  child.lua(string.format("require('bib').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir_a, "missing.sqlite")))
  child.lua(string.format("vim.cmd.edit(%q)", md_a))
  local first = u.lsp_request(child, "textDocument/completion", { line = 4, character = 7 })

  child.lua(string.format("vim.cmd.edit(%q)", md_b))
  local second = u.lsp_request(child, "textDocument/completion", { line = 4, character = 7 })

  eq(#first.result.items, 1)
  eq(first.result.items[1].textEdit.newText, "commonAlpha")
  eq(#second.result.items, 1)
  eq(second.result.items[1].textEdit.newText, "commonBeta")
end

T["lsp_handlers"]["resolves completion from its source buffer"] = function()
  local dir_a, dir_b = u.temp_dir(), u.temp_dir()
  local md_a, md_b = vim.fs.joinpath(dir_a, "a.md"), vim.fs.joinpath(dir_b, "b.md")
  u.write_file(child, vim.fs.joinpath(dir_a, "a.bib"), "@article{same, title = {Alpha}}")
  u.write_file(child, vim.fs.joinpath(dir_b, "b.bib"), "@article{same, title = {Beta}}")
  u.write_file(child, md_a, "---\nbibliography: a.bib\n---\n\nSee @sa")
  u.write_file(child, md_b, "---\nbibliography: b.bib\n---\n\nSee @sa")

  local result = child.lua(string.format(
    [[
    require('bib').setup({ zotero = { database = %q } })
    local function open(path)
      vim.cmd.edit(path)
      local bufnr = vim.api.nvim_get_current_buf()
      local client
      assert(vim.wait(3000, function()
        client = vim.lsp.get_clients({ bufnr = bufnr, name = 'bib_ls' })[1]
        return client and client.initialized
      end))
      return bufnr, client
    end
    local function request(client, bufnr, method, params)
      local result
      assert(client:request(method, params, function(err, value) assert(not err, err and err.message); result = value end, bufnr))
      assert(vim.wait(3000, function() return result ~= nil end))
      return result
    end
    local a, client_a = open(%q)
    local first = request(client_a, a, 'textDocument/completion', {
      textDocument = { uri = vim.uri_from_bufnr(a) }, position = { line = 4, character = 6 },
    })
    local b, client_b = open(%q)
    local second = request(client_b, b, 'textDocument/completion', {
      textDocument = { uri = vim.uri_from_bufnr(b) }, position = { line = 4, character = 6 },
    })
    local resolved = request(client_b, b, 'completionItem/resolve', first.items[1])
    return { first = first, second = second, resolved = resolved }
	]],
    vim.fs.joinpath(dir_a, "missing.sqlite"),
    md_a,
    md_b
  ))

  eq(#result.first.items, 1)
  eq(#result.second.items, 1)
  eq(result.resolved.documentation.value:find("Alpha", 1, true) ~= nil, true)
end

vim
  .iter({
    { name = "open failure", failure = "open", notification = "injected open failure" },
    { name = "open and close failures", failure = "open_close", notification = "injected open failure", warning = "injected close failure" },
    { name = "query failure", failure = "query", notification = "injected query failure" },
    { name = "close failure", failure = "close", response = "injected close failure" },
    { name = "query and close failures", failure = "query_close", notification = "injected query failure", warning = "injected close failure" },
  })
  :each(function(case)
    T["lsp_handlers"]["code action reports " .. case.name .. " and recovers"] = function()
      local dir = u.temp_dir()
      local db = u.setup_zotero_db(child, dir)
      local md = vim.fs.joinpath(dir, "paper.md")
      u.write_file(child, md, "# Zotero\n\nSee @ABC123#smith2020.")
      child.lua(string.format("require('bib').setup({ zotero = { database = %q } }); vim.cmd.edit(%q)", db, md))
      local position = { line = 2, character = 13 }
      eq(u.lsp_request(child, "textDocument/hover", position).err, vim.NIL)
      child.lua(string.format(
        [[
      local failure = %q
      local sqlite = require('sqlite')
      local original = package.loaded.sqlite
      package.loaded.sqlite = { new = function(...)
        local db = sqlite.new(...)
        local open, eval, close = db.open, db.eval, db.close
        if failure == 'open' or failure == 'open_close' then
          db.open = function(self, ...) open(self, ...); error('injected open failure') end
        end
        if failure == 'query' or failure == 'query_close' then
          db.eval = function() error('injected query failure') end
        end
        if failure == 'close' or failure == 'open_close' or failure == 'query_close' then
          db.close = function(self, ...) close(self, ...); error('injected close failure') end
        end
        return db
      end }
      _G.restore_sqlite = function() package.loaded.sqlite = original end
      _G.messages, _G.warnings = {}, {}
      vim.notify = function(message) table.insert(_G.messages, message) end
      vim.lsp.log.warn = function(message) table.insert(_G.warnings, message) end
    ]],
        case.failure
      ))
      local response = u.lsp_request(child, "textDocument/codeAction", position)
      local recorded = child.lua([[_G.restore_sqlite(); return { messages = _G.messages, warnings = _G.warnings }]])

      eq(response.calls, 1)
      if case.response then
        eq(response.err.code, vim.lsp.protocol.ErrorCodes.InternalError)
        eq(response.err.message:find(case.response, 1, true) ~= nil, true)
      else
        eq(response.err, vim.NIL)
        eq(response.result, {})
        eq(#recorded.messages, 1)
        eq(recorded.messages[1]:find(case.notification, 1, true) ~= nil, true)
      end
      if case.warning then
        eq(#recorded.warnings, 1)
        eq(recorded.warnings[1]:find(case.warning, 1, true) ~= nil, true)
      else
        eq(recorded.warnings, {})
      end
      local recovered = u.lsp_request(child, "textDocument/codeAction", position)
      eq(recovered.err, vim.NIL)
      eq(#recovered.result, 2)
    end
  end)

T["lsp_handlers"]["code action returns pdf and note for zotero citation"] = function()
  local dir = u.temp_dir()
  local db_path = u.setup_zotero_db(child, dir)
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, md, "# Hello\n\nSee @ABC123#smith2020.")
  child.lua(string.format("vim.cmd.edit(%q)", md))
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } })", db_path))

  local r = u.lsp_request(child, "textDocument/codeAction", { line = 2, character = 13 })

  eq(r.err, vim.NIL)
  eq(#r.result, 2)

  local titles = vim.iter(r.result):map(function(a) return a.title end):totable()

  eq(titles[1], "Open PDF")
  eq(titles[2], "Get notes from Zotero")
  eq(r.result[1].command.arguments[1], vim.fs.joinpath(dir, "test.pdf"))
  eq(r.result[2].edit.changes[vim.uri_from_fname(md)][1].newText:find("A note about stuff.", 1, true) ~= nil, true)
end

T["lsp_handlers"]["unknown requests return one empty response"] = function()
  setup_handler("---\nbibliography: refs.bib\n---\n\nSee @smi")
  local result = child.lua([[
    local client
    assert(vim.wait(3000, function()
      client = vim.lsp.get_clients({ bufnr = 0, name = 'bib_ls' })[1]
      return client and client.initialized
    end))
    local calls, response = 0, nil
    local accepted = client:request('unknown/method', {}, function(err, value)
      calls = calls + 1
      response = { err = err or vim.NIL, value = value or vim.NIL }
    end, 0)
    assert(vim.wait(3000, function() return response ~= nil end))
    return { accepted = accepted, calls = calls, response = response }
  ]])

  eq(result, { accepted = true, calls = 1, response = { err = vim.NIL, value = vim.NIL } })
end

T["lsp_handlers"]["unknown notifications do not stop the client"] = function()
  setup_handler("---\nbibliography: refs.bib\n---\n\nSee @smi")
  child.lua([[
    assert(vim.wait(3000, function() return #vim.lsp.get_clients({ bufnr = 0, name = 'bib_ls' }) > 0 end))
    vim.lsp.get_clients({ bufnr = 0, name = 'bib_ls' })[1]:notify('unknown/method', {})
  ]])
  local response = u.lsp_request(child, "textDocument/completion", { line = 4, character = 7 })
  eq(response.result.items[1].textEdit.newText, "smith2020")
end

T["lsp_handlers"]["scheduled completion failures return an error"] = function()
  setup_handler("---\nbibliography: refs.bib\n---\n\nSee @smi")
  u.lsp_request(child, "textDocument/completion", { line = 4, character = 7 })
  child.lua("_G.original_get_node = vim.treesitter.get_node; vim.treesitter.get_node = function() error('expected failure') end")
  local response = u.lsp_request(child, "textDocument/completion", { line = 4, character = 7 })
  child.lua("vim.treesitter.get_node = _G.original_get_node; _G.original_get_node = nil")

  eq(response.err.code, vim.lsp.protocol.ErrorCodes.InternalError)
  eq(response.err.message:find("expected failure", 1, true) ~= nil, true)
end

T["lsp_handlers"]["Zotero note conversion does not block code actions"] = function()
  local dir = u.temp_dir()
  local db_path = u.setup_zotero_db(child, dir)
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, md, "# Hello\n\nSee @ABC123#smith2020.")
  child.lua(string.format("vim.cmd.edit(%q)", md))
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } })", db_path))
  local result = child.lua([[
    local client
    assert(vim.wait(3000, function()
      client = vim.lsp.get_clients({ bufnr = 0, name = 'bib_ls' })[1]
      return client and client.initialized
    end))
    local finish, response
    local original = vim.system
    vim.system = function(_, _, callback)
      finish = callback
      return { wait = function() error('conversion blocked') end }
    end
    local position = { line = 2, character = 13 }
    local ok = client:request('textDocument/codeAction', {
      textDocument = { uri = vim.uri_from_bufnr(0) },
      range = { start = position, ['end'] = position }, context = { diagnostics = {} },
    }, function(err, actions) response = { err = err, actions = actions } end, 0)
    assert(vim.wait(3000, function() return finish ~= nil end))
    local pending = response == nil
    finish({ code = 0, stdout = 'Converted note' })
    assert(vim.wait(3000, function() return response ~= nil end))
    vim.system = original
    local action = response.actions and response.actions[2]
    return { ok = ok, pending = pending, text = action and action.edit.changes[vim.uri_from_bufnr(0)][1].newText }
  ]])

  eq(result, { ok = true, pending = true, text = "Converted note\n" })
end

T["lsp_handlers"]["uses the original note when pandoc is unavailable"] = function()
  local dir = u.temp_dir()
  local db_path = u.setup_zotero_db(child, dir)
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, md, "# Hello\n\nSee @ABC123#smith2020.")
  child.lua(string.format(
    [[
    local db = require('sqlite').new(%q)
    db:open()
    db:eval("UPDATE itemNotes SET note = '<p>Original note</p>' WHERE itemID = 1")
    db:close()
    vim.cmd.edit(%q)
    require('bib').setup({ zotero = { database = %q } })
    _G.original_path = vim.env.PATH
    vim.env.PATH = %q
  ]],
    db_path,
    md,
    db_path,
    dir
  ))

  local response = u.lsp_request(child, "textDocument/codeAction", { line = 2, character = 13 })
  child.lua("vim.env.PATH = _G.original_path; _G.original_path = nil")
  eq(response.err, vim.NIL)
  eq(response.result[2].edit.changes[vim.uri_from_fname(md)][1].newText, "<p>Original note</p>\n")
end

T["lsp_handlers"]["note conversion preserves order and falls back after timeout"] = function()
  local dir = u.temp_dir()
  local db_path = u.setup_zotero_db(child, dir)
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, md, "# Hello\n\nSee @ABC123#smith2020.")
  local result = child.lua(string.format(
    [[
    local db = require('sqlite').new(%q)
    db:open()
    db:eval("UPDATE itemNotes SET note = 'first html' WHERE itemID = 1")
    db:eval("INSERT INTO itemNotes VALUES (3, 1, 'second html', 'Note 2')")
    db:close()
    vim.cmd.edit(%q)
    require('bib').setup({ zotero = { database = %q } })
    local client
    assert(vim.wait(3000, function()
      client = vim.lsp.get_clients({ bufnr = 0, name = 'bib_ls' })[1]
      return client and client.initialized
    end))
    local jobs, response = {}, nil
    local original = vim.system
    vim.system = function(_, opts, callback)
      table.insert(jobs, { stdin = opts.stdin, timeout = opts.timeout, finish = callback })
      return {}
    end
    local position = { line = 2, character = 13 }
    assert(client:request('textDocument/codeAction', {
      textDocument = { uri = vim.uri_from_bufnr(0) }, range = { start = position, ['end'] = position },
      context = { diagnostics = {} },
    }, function(err, actions) assert(not err, err and err.message); response = actions end, 0))
    assert(vim.wait(3000, function() return #jobs == 1 end))
    jobs[1].finish({ code = 0, stdout = 'first converted' })
    assert(vim.wait(3000, function() return #jobs == 2 end))
    jobs[2].finish({ code = 124 })
    assert(vim.wait(3000, function() return response ~= nil end))
    vim.system = original
    return { first = jobs[1].stdin, second = jobs[2].stdin, timeout = jobs[2].timeout,
      text = response[2].edit.changes[vim.uri_from_bufnr(0)][1].newText }
  ]],
    db_path,
    md,
    db_path
  ))

  eq(result, { first = "first html", second = "second html", timeout = 5000, text = "first converted\n\nsecond html\n" })
end

T["lsp_start"]["a buffer without a backend does not stop a shared client"] = function()
  local dir = u.temp_dir()
  local first, second = vim.fs.joinpath(dir, "first.md"), vim.fs.joinpath(dir, "second.md")
  u.write_file(child, vim.fs.joinpath(dir, "refs.bib"), entry)
  u.write_file(child, first, "---\nbibliography: refs.bib\n---\n\nSee @smi")
  u.write_file(child, second, "# No bibliography")
  local result = child.lua(string.format(
    [[
    local second = %q
    local second_attached = false
    vim.api.nvim_create_autocmd('LspAttach', { callback = function(args)
      if vim.api.nvim_buf_get_name(args.buf) == second then second_attached = true end
    end })
    require('bib').setup({ zotero = { database = %q } })
    vim.cmd.edit(%q)
    local first = vim.api.nvim_get_current_buf()
    assert(vim.wait(3000, function() return #vim.lsp.get_clients({ bufnr = first, name = 'bib_ls' }) > 0 end))
    local client = vim.lsp.get_clients({ bufnr = first, name = 'bib_ls' })[1]
    vim.cmd.edit(second)
    assert(vim.wait(3000, function() return second_attached end))
    vim.wait(100)
    local alive = not client:is_stopped() and vim.lsp.buf_is_attached(first, client.id)
    local completion
    if alive then
      client:request('textDocument/completion', {
        textDocument = { uri = vim.uri_from_bufnr(first) }, position = { line = 4, character = 7 },
      }, function(_, value) completion = value end, first)
      vim.wait(3000, function() return completion ~= nil end)
    end
    return { alive = alive, count = completion and #completion.items or 0 }
  ]],
    second,
    vim.fs.joinpath(dir, "missing.sqlite"),
    first
  ))

  eq(result, { alive = true, count = 1 })
end

T["lsp_handlers"]["saving a bibliography refreshes only its dependent buffers"] = function()
  local shared, other, zotero = u.temp_dir(), u.temp_dir(), u.temp_dir()
  local refs, other_refs = vim.fs.joinpath(shared, "refs.bib"), vim.fs.joinpath(other, "other.bib")
  local first, second = vim.fs.joinpath(shared, "first.md"), vim.fs.joinpath(shared, "second.md")
  local unrelated, zotero_doc = vim.fs.joinpath(other, "other.md"), vim.fs.joinpath(zotero, "zotero.md")
  u.write_file(child, refs, entry)
  u.write_file(child, other_refs, "@article{other, title = {Other}}")
  u.write_file(child, first, "---\nbibliography: refs.bib\n---\n\nSee @added.")
  u.write_file(child, second, "---\nbibliography: refs.bib\n---\n\nSee @added.")
  u.write_file(child, unrelated, "---\nbibliography: other.bib\n---\n\nSee @other.")
  u.write_file(child, zotero_doc, "# Zotero\n\nSee @ABC123#smith2020.")
  local db = u.setup_zotero_db(child, zotero)
  local result = child.lua(string.format(
    [[
    require('bib').setup({ zotero = { database = %q } })
    local function open(path)
      vim.cmd.edit(path)
      local buf, client = vim.api.nvim_get_current_buf(), nil
      assert(vim.wait(3000, function()
        client = vim.lsp.get_clients({ bufnr = buf, name = 'bib_ls' })[1]
        return client and client.initialized
      end))
      return { buf = buf, client = client }
    end
    local function request(doc, method, position)
      local response = assert(doc.client:request_sync(method, {
        textDocument = { uri = vim.uri_from_bufnr(doc.buf) }, position = position,
      }, 3000, doc.buf))
      assert(not response.err, response.err and response.err.message)
      return response.result
    end
    local first, second, other, zotero = open(%q), open(%q), open(%q), open(%q)
    local db = require('sqlite').new(%q)
    db:open()
    db:eval("UPDATE itemDataValues SET value = 'Changed' WHERE valueID = 1")
    db:close()
    vim.cmd.edit(%q)
    vim.api.nvim_buf_set_lines(0, -1, -1, false, { '@book{added, title = {Added}}' })
    vim.cmd.write()
    return {
      first = request(first, 'textDocument/definition', { line = 4, character = 8 }).uri,
      second = request(second, 'textDocument/definition', { line = 4, character = 8 }).uri,
      other = request(other, 'textDocument/definition', { line = 4, character = 8 }).uri,
      zotero = request(zotero, 'textDocument/hover', { line = 2, character = 13 }).contents.value,
    }
  ]],
    db,
    first,
    second,
    unrelated,
    zotero_doc,
    db,
    refs
  ))

  eq(result.first, vim.uri_from_fname(refs))
  eq(result.second, vim.uri_from_fname(refs))
  eq(result.other, vim.uri_from_fname(other_refs))
  eq(result.zotero:find("Test Title", 1, true) ~= nil, true)
end

T["lsp_handlers"]["reports returned and thrown PDF open errors"] = function()
  local dir = setup_handler("---\nbibliography: refs.bib\n---\n\nSee @smith2020")
  local pdf = vim.fs.joinpath(dir, "test.pdf")
  u.write_file(child, pdf, "%PDF-1.4\n%%EOF")
  local result = child.lua(string.format(
    [[
    local client
    assert(vim.wait(3000, function()
      client = vim.lsp.get_clients({ bufnr = 0, name = 'bib_ls' })[1]
      return client and client.initialized
    end))
    local messages, responses = {}, {}
    vim.notify = function(message) table.insert(messages, message) end
    local function run()
      local response = assert(client:request_sync('workspace/executeCommand', {
        command = 'bib.open_pdf', arguments = { %q },
      }, 3000, 0))
      table.insert(responses, response.err and response.err.message or vim.NIL)
    end
    vim.ui.open = function() return nil, 'no handler' end
    run()
    vim.ui.open = function() error('spawn failed') end
    run()
    vim.ui.open = function() return {} end
    run()
    return { messages = messages, responses = responses }
  ]],
    pdf
  ))

  eq(#result.responses, 3)
  eq(type(result.responses[1]), "string")
  eq(result.responses[1]:find("no handler", 1, true) ~= nil, true)
  eq(result.responses[2]:find("spawn failed", 1, true) ~= nil, true)
  eq(result.responses[3], vim.NIL)
  eq(#result.messages, 2)
  eq(result.messages[1]:find("no handler", 1, true) ~= nil, true)
  eq(result.messages[2]:find("spawn failed", 1, true) ~= nil, true)
end

T["lsp_handlers"]["rejects a non-string PDF path"] = function()
  setup_handler("---\nbibliography: refs.bib\n---\n\nSee @smith2020")
  local result = child.lua([[
    local client
    assert(vim.wait(3000, function()
      client = vim.lsp.get_clients({ bufnr = 0, name = 'bib_ls' })[1]
      return client and client.initialized
    end))
    local opened, codes = {}, {}
    vim.ui.open = function(path) table.insert(opened, path); return {} end
    vim.iter({ 17, false }):each(function(path)
      local response = assert(client:request_sync('workspace/executeCommand', {
        command = 'bib.open_pdf', arguments = { path },
      }, 3000, 0))
      table.insert(codes, response.err and response.err.code or vim.NIL)
    end)
    return { opened = opened, codes = codes }
  ]])

  eq(result, { opened = {}, codes = { vim.lsp.protocol.ErrorCodes.InvalidParams, vim.lsp.protocol.ErrorCodes.InvalidParams } })
end

T["lsp_start"]["logs the missing bibliography parser when no backend loads"] = function()
  local dir = u.temp_dir()
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, vim.fs.joinpath(dir, "refs.bib"), entry)
  u.write_file(child, md, "---\nbibliography: refs.bib\n---\n")
  local result = child.lua(string.format(
    [[
    local original = vim.treesitter.get_parser
    vim.treesitter.get_parser = function(buf, lang, ...)
      if lang == 'bibtex' then error('BibTeX parser unavailable') end
      return original(buf, lang, ...)
    end
    local messages, warnings = {}, {}
    vim.notify = function(message) table.insert(messages, message) end
    vim.lsp.log.warn = function(message) table.insert(warnings, message) end
    require('bib').setup({ zotero = { database = %q } })
    vim.cmd.edit(%q)
    vim.cmd('Bib')
    assert(vim.wait(3000, function() return vim.list_contains(messages, 'No entries found') end))
    vim.treesitter.get_parser = original
    return { shown = vim.list_contains(messages, 'No entries found'),
      logged = vim.iter(warnings):any(function(message)
        return message:find('[bib] search backend failed:', 1, true) ~= nil
          and message:find('BibTeX parser unavailable', 1, true) ~= nil
      end) }
  ]],
    vim.fs.joinpath(dir, "missing.sqlite"),
    md
  ))

  eq(result, { shown = true, logged = true })
end

T["lsp_handlers"]["completes and resolves LaTeX citations from addbibresource"] = function()
  local dir = u.temp_dir()
  local tex, refs = vim.fs.joinpath(dir, "paper.tex"), vim.fs.joinpath(dir, "refs.bib")
  u.write_file(child, refs, entry)
  u.write_file(child, tex, "\\documentclass{article}\n\\addbibresource{refs.bib}\n\\begin{document}\nSee \\cite{smith2020}.\n\\end{document}")
  child.lua(string.format("vim.cmd.edit(%q)", tex))
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir, "missing.sqlite")))

  local completion = u.lsp_request(child, "textDocument/completion", { line = 3, character = 13 })
  local definition = u.lsp_request(child, "textDocument/definition", { line = 3, character = 13 })

  eq(completion.err, vim.NIL)
  eq(completion.result.items[1].textEdit.newText, "smith2020")
  eq(definition.err, vim.NIL)
  eq(definition.result.uri, vim.uri_from_fname(refs))
end

T["lsp_handlers"]["LaTeX citation lookup selects the key under the cursor"] = function()
  local dir = u.temp_dir()
  local tex, refs = vim.fs.joinpath(dir, "paper.tex"), vim.fs.joinpath(dir, "refs.bib")
  local line = "See \\cite{smith2020, other} and \\textbf{smith2020}."
  u.write_file(child, refs, entry .. "\n@book{other, title = {Other}}")
  u.write_file(child, tex, "\\bibliography{refs}\n\\begin{document}\n" .. line .. "\n\\end{document}")
  child.lua(string.format("vim.cmd.edit(%q)", tex))
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir, "missing.sqlite")))

  local other_col = assert(line:find("other", 1, true))
  local plain_col = assert(line:find("smith2020", assert(line:find("textbf", 1, true)), true))
  local definition = u.lsp_request(child, "textDocument/definition", { line = 2, character = other_col })
  local plain = u.lsp_request(child, "textDocument/definition", { line = 2, character = plain_col })

  eq(definition.result.uri, vim.uri_from_fname(refs))
  eq(definition.result.range.start.line, 5)
  eq(plain.result, vim.NIL)
end

vim.iter({ "textDocument/hover", "textDocument/completion", "textDocument/definition", "textDocument/codeAction" }):each(function(method)
  T["lsp_handlers"][method .. " reports returned citation parser errors once"] = function()
    setup_handler("---\nbibliography: refs.bib\n---\n\nSee @smith2020\n")
    u.lsp_request(child, "textDocument/hover", { line = 4, character = 8 })
    child.lua([[
      _G.original_get_parser = vim.treesitter.get_parser
      vim.treesitter.get_parser = function(buf, lang, ...)
        if lang == 'markdown' then return nil, 'returned citation parser error' end
        return _G.original_get_parser(buf, lang, ...)
      end
    ]])
    local response = u.lsp_request(child, method, { line = 4, character = 8 })
    child.lua("vim.treesitter.get_parser = _G.original_get_parser; _G.original_get_parser = nil")

    eq(response.calls, 1)
    eq(response.err.message, "returned citation parser error")
  end
end)

T["lsp_handlers"]["returned parser errors preserve the previous bibliography on reload"] = function()
  local dir = u.temp_dir()
  local refs, md = vim.fs.joinpath(dir, "refs.bib"), vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, refs, entry)
  u.write_file(child, md, "---\nbibliography: refs.bib\n---\n\nSee @smith2020.")
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } }); vim.cmd.edit(%q)", vim.fs.joinpath(dir, "missing.sqlite"), md))
  local position = { line = 4, character = 8 }
  eq(u.lsp_request(child, "textDocument/definition", position).result.uri, vim.uri_from_fname(refs))
  local messages = child.lua([[
    local original = vim.treesitter.get_parser
    vim.treesitter.get_parser = function(bufnr, lang, ...)
      if lang == 'bibtex' then return nil, 'returned reload parser error' end
      return original(bufnr, lang, ...)
    end
    local messages = {}
    vim.notify = function(message) table.insert(messages, message) end
    vim.cmd.write()
    vim.treesitter.get_parser = original
    return messages
  ]])

  local definition = u.lsp_request(child, "textDocument/definition", position)
  eq(definition.result.uri, vim.uri_from_fname(refs))
  eq(#messages, 1)
  eq(messages[1]:find("returned reload parser error", 1, true) ~= nil, true)
end

T["lsp_handlers"]["document save preserves the previous bibliography when reload fails"] = function()
  local dir = u.temp_dir()
  local first, second = vim.fs.joinpath(dir, "refs.bib"), vim.fs.joinpath(dir, "next.bib")
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, first, entry)
  u.write_file(child, second, "@book{new, title = {New}}")
  u.write_file(child, md, "---\nbibliography: refs.bib\n---\n\nSee @smith2020.")
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } }); vim.cmd.edit(%q)", vim.fs.joinpath(dir, "missing.sqlite"), md))
  local position = { line = 4, character = 8 }
  eq(u.lsp_request(child, "textDocument/definition", position).result.uri, vim.uri_from_fname(first))
  local messages = child.lua([[
    vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'bibliography: next.bib' })
    local original = vim.treesitter.get_parser
    vim.treesitter.get_parser = function(bufnr, lang, ...)
      if lang == 'bibtex' then error('injected reload failure') end
      return original(bufnr, lang, ...)
    end
    local messages = {}
    vim.notify = function(message) table.insert(messages, message) end
    vim.cmd.write()
    vim.treesitter.get_parser = original
    return messages
  ]])

  local definition = u.lsp_request(child, "textDocument/definition", position)
  eq(definition.result.uri, vim.uri_from_fname(first))
  eq(#messages, 1)
  eq(messages[1]:find("injected reload failure", 1, true) ~= nil, true)
end

T["lsp_handlers"]["bibliography save reports one reload error and preserves dependent buffers"] = function()
  local dir = u.temp_dir()
  local refs = vim.fs.joinpath(dir, "refs.bib")
  local first, second = vim.fs.joinpath(dir, "first.md"), vim.fs.joinpath(dir, "second.md")
  u.write_file(child, refs, entry)
  u.write_file(child, first, "---\nbibliography: refs.bib\n---\n\nSee @smith2020.")
  u.write_file(child, second, "---\nbibliography: refs.bib\n---\n\nSee @smith2020.")
  local result = child.lua(string.format(
    [[
    require('bib').setup({ zotero = { database = %q } })
    local function open(path)
      vim.cmd.edit(path)
      local buf, client = vim.api.nvim_get_current_buf(), nil
      assert(vim.wait(3000, function()
        client = vim.lsp.get_clients({ bufnr = buf, name = 'bib_ls' })[1]
        return client and client.initialized
      end))
      return { buf = buf, client = client }
    end
    local function hover(doc)
      local response = assert(doc.client:request_sync('textDocument/hover', {
        textDocument = { uri = vim.uri_from_bufnr(doc.buf) }, position = { line = 4, character = 8 },
      }, 3000, doc.buf))
      assert(not response.err, response.err and response.err.message)
      return response.result.contents.value
    end
    local first, second = open(%q), open(%q)
    vim.cmd.edit(%q)
    vim.api.nvim_buf_set_lines(0, -1, -1, false, { '@book{new, title={New}}' })
    local original = vim.treesitter.get_parser
    vim.treesitter.get_parser = function(buf, lang, ...)
      if lang == 'bibtex' then error('injected bibliography failure') end
      return original(buf, lang, ...)
    end
    local messages = {}
    vim.notify = function(message) table.insert(messages, message) end
    vim.cmd.write()
    vim.treesitter.get_parser = original
    return { first = hover(first), second = hover(second), messages = messages }
  ]],
    vim.fs.joinpath(dir, "missing.sqlite"),
    first,
    second,
    refs
  ))

  eq(result.first:find("Test", 1, true) ~= nil, true)
  eq(result.second:find("Test", 1, true) ~= nil, true)
  eq(#result.messages, 1)
  eq(result.messages[1]:find("injected bibliography failure", 1, true) ~= nil, true)
end
return T
