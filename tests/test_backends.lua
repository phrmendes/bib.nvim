local test = require("mini.test")
local u = dofile("tests/utils.lua")
local eq = test.expect.equality

local child, T = u.new_child_set()

local entry = "@article{smith2020,\n  author = {John Smith},\n  title = {Test},\n  year = {2020}\n}"

--- Open a citation with an attached bibliography client.
---@return string refs Path to the bibliography.
local function open_citation()
  local dir = u.temp_dir()
  local refs, md = vim.fs.joinpath(dir, "refs.bib"), vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, refs, entry)
  u.write_file(child, md, "---\nbibliography: refs.bib\n---\n\nSee @smith2020.")
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } }); vim.cmd.edit(%q)", vim.fs.joinpath(dir, "missing.sqlite"), md))
  eq(u.lsp_request(child, "textDocument/definition", { line = 4, character = 8 }).result.uri, vim.uri_from_fname(refs))
  return refs
end

T["query_errors"] = test.new_set()

vim.iter({ { name = "strings", marker = "(string" }, { name = "entries", marker = "(entry" } }):each(function(case)
  T["query_errors"][case.name .. " query failures reach the command"] = function()
    local dir = u.temp_dir()
    local md = vim.fs.joinpath(dir, "paper.md")
    u.write_file(child, vim.fs.joinpath(dir, "refs.bib"), entry)
    u.write_file(child, md, "---\nbibliography: refs.bib\n---\n\nSee @smith2020.")
    local result = child.lua(string.format(
      [[
        local parse = vim.treesitter.query.parse
        vim.treesitter.query.parse = function(lang, text)
          local query = parse(lang, text)
          if lang == "bibtex" and text:find(%q, 1, true) then query.iter_matches = function() error("query iteration failed") end end
          return query
        end
        local messages, warnings = {}, {}
        vim.notify = function(message) table.insert(messages, message) end
        vim.lsp.log.warn = function(message) table.insert(warnings, message) end
        require("bib").setup({ zotero = { database = %q } })
        vim.cmd.edit(%q)
        vim.cmd("Bib")
        assert(vim.wait(3000, function() return vim.list_contains(messages, "No entries found") end))
        vim.treesitter.query.parse = parse
        return { messages = messages, warnings = warnings }
      ]],
      case.marker,
      vim.fs.joinpath(dir, "missing.sqlite"),
      md
    ))

    eq(vim.list_contains(result.messages, "No entries found"), true)
    eq(vim.iter(result.warnings):any(function(message) return message:find("query iteration failed", 1, true) ~= nil end), true)
  end
end)

T["parser_returns"] = test.new_set()

vim.iter({ "bibtex", "markdown", "yaml", "latex" }):each(function(language)
  T["parser_returns"][language .. " reports a parser error without leaking buffers"] = function()
    local dir = u.temp_dir()
    local path = vim.fs.joinpath(dir, language == "latex" and "paper.tex" or "paper.md")
    local content = language == "latex" and "\\bibliography{refs}\n\\begin{document}\nSee \\cite{smith2020}.\n\\end{document}" or "---\nbibliography: refs.bib\n---\n\nSee @smith2020."
    u.write_file(child, vim.fs.joinpath(dir, "refs.bib"), entry)
    u.write_file(child, path, content)
    local result = child.lua(string.format(
      [[
        local language, path = %q, %q
        local original = vim.treesitter.get_parser
        vim.treesitter.get_parser = function(buf, lang, ...)
          if lang == language then return nil, "returned " .. language .. " parser error" end
          return original(buf, lang, ...)
        end
        local messages, warnings = {}, {}
        vim.notify = function(message) table.insert(messages, message) end
        vim.lsp.log.warn = function(message) table.insert(warnings, message) end
        require("bib").setup({ zotero = { database = %q } })
        vim.cmd.edit(path)
        local before = #vim.api.nvim_list_bufs()
        vim.cmd("Bib")
        assert(vim.wait(3000, function() return vim.list_contains(messages, "No entries found") end))
        vim.treesitter.get_parser = original
        return { before = before, after = #vim.api.nvim_list_bufs(), messages = messages, warnings = warnings }
      ]],
      language,
      path,
      vim.fs.joinpath(dir, "missing.sqlite")
    ))

    eq(result.after, result.before)
    eq(vim.list_contains(result.messages, "No entries found"), true)
    eq(vim.iter(result.warnings):any(function(message) return message:find("returned " .. language .. " parser error", 1, true) ~= nil end), true)
  end
end)

T["load"] = test.new_set()

vim
  .iter({
    { name = "search finds bibliography entries", has_bib = true },
    { name = "search reports when no backend has entries", has_bib = false },
  })
  :each(function(case)
    T["load"][case.name] = function()
      local dir = u.temp_dir()
      local md = vim.fs.joinpath(dir, "paper.md")
      if case.has_bib then u.write_file(child, vim.fs.joinpath(dir, "refs.bib"), entry) end
      u.write_file(child, md, case.has_bib and "---\nbibliography: refs.bib\n---\n" or "# No bib")
      local result = child.lua(string.format(
        [[
          local items, messages = nil, {}
          vim.ui.select = function(value) items = value end
          vim.notify = function(message) table.insert(messages, message) end
          require("bib").setup({ zotero = { database = %q } })
          vim.cmd.edit(%q)
          vim.cmd("Bib")
          assert(vim.wait(3000, function() return items ~= nil or vim.list_contains(messages, "No entries found") end))
          return { count = items and #items or 0, missing = vim.list_contains(messages, "No entries found") }
        ]],
        vim.fs.joinpath(dir, "missing.sqlite"),
        md
      ))

      eq(result, { count = case.has_bib and 1 or 0, missing = not case.has_bib })
    end
  end)

T["parse"] = test.new_set()

T["parse"]["reload preserves an open modified bibliography buffer"] = function()
  local dir = u.temp_dir()
  local bib_path, md = vim.fs.joinpath(dir, "refs.bib"), vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, bib_path, entry)
  u.write_file(child, md, "---\nbibliography: refs.bib\n---\n\nSee @smith2020.")
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } }); vim.cmd.edit(%q)", vim.fs.joinpath(dir, "missing.sqlite"), md))
  local position = { line = 4, character = 8 }
  eq(u.lsp_request(child, "textDocument/definition", position).result.uri, vim.uri_from_fname(bib_path))

  local bib_buf = child.lua(string.format(
    [[
      vim.cmd.edit(%q)
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "@article{unsaved," })
      vim.cmd.edit(%q)
      vim.cmd.write()
      return buf
    ]],
    bib_path,
    md
  ))

  eq(child.api.nvim_buf_is_valid(bib_buf), true)
  eq(child.api.nvim_buf_get_lines(bib_buf, 0, 1, false), { "@article{unsaved," })
  eq(child.lua_get(string.format("vim.bo[%d].modified", bib_buf)), true)
  eq(u.lsp_request(child, "textDocument/definition", position).result.uri, vim.uri_from_fname(bib_path))
end

T["parse"]["deletes its scratch buffer when the parser fails"] = function()
  local refs = open_citation()
  local result = child.lua([[
    local before = #vim.api.nvim_list_bufs()
    local original = vim.treesitter.get_parser
    vim.treesitter.get_parser = function(buf, lang, ...)
      if lang == "bibtex" then error("parser failure") end
      return original(buf, lang, ...)
    end
    local messages = {}
    vim.notify = function(message) table.insert(messages, message) end
    vim.cmd.write()
    vim.treesitter.get_parser = original
    return { messages = messages, before = before, after = #vim.api.nvim_list_bufs() }
  ]])

  eq(result.after, result.before)
  eq(#result.messages, 1)
  eq(result.messages[1]:find("parser failure", 1, true) ~= nil, true)
  eq(u.lsp_request(child, "textDocument/definition", { line = 4, character = 8 }).result.uri, vim.uri_from_fname(refs))
end

T["parse"]["keeps hash characters inside visible fields"] = function()
  local dir = u.temp_dir()
  local refs, md = vim.fs.joinpath(dir, "refs.bib"), vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, refs, "@book{knuth, title = {C# in Depth}, author = {A#B}}")
  u.write_file(child, md, "---\nbibliography: refs.bib\n---\n\nSee @knuth.")
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } }); vim.cmd.edit(%q)", vim.fs.joinpath(dir, "missing.sqlite"), md))

  local response = u.lsp_request(child, "textDocument/hover", { line = 4, character = 8 })
  eq(response.err, vim.NIL)
  eq(response.result.contents.value, "# A#B - C# in Depth")
end

T["parse"]["expands macros only when the value is not quoted"] = function()
  local dir = u.temp_dir()
  local refs, md = vim.fs.joinpath(dir, "refs.bib"), vim.fs.joinpath(dir, "paper.md")
  u.write_file(
    child,
    refs,
    [[@string{journal = {Expanded}}
@article{example, title = {journal}, author = journal}]]
  )
  u.write_file(child, md, "---\nbibliography: refs.bib\n---\n\nSee @example.")
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } }); vim.cmd.edit(%q)", vim.fs.joinpath(dir, "missing.sqlite"), md))

  local response = u.lsp_request(child, "textDocument/hover", { line = 4, character = 8 })
  eq(response.err, vim.NIL)
  eq(response.result.contents.value, "# Expanded - journal")
end

T["parse"]["resolves shared macros across multiple entries and fields"] = function()
  local dir = u.temp_dir()
  local refs, md = vim.fs.joinpath(dir, "refs.bib"), vim.fs.joinpath(dir, "paper.md")
  u.write_file(
    child,
    refs,
    [[@string{journal = {Expanded}}
@article{first, title = {First}, author = journal}
@article{second, title = {Second}, author = journal}]]
  )
  u.write_file(child, md, "---\nbibliography: refs.bib\n---\n\nSee @first.\n\nSee @second.")
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } }); vim.cmd.edit(%q)", vim.fs.joinpath(dir, "missing.sqlite"), md))

  local first = u.lsp_request(child, "textDocument/hover", { line = 4, character = 8 })
  local second = u.lsp_request(child, "textDocument/hover", { line = 6, character = 8 })
  eq(first.result.contents.value, "# Expanded - First")
  eq(second.result.contents.value, "# Expanded - Second")
end

T["resolve concatenation"] = test.new_set()

vim
  .iter({
    { name = "quoted hash stays in the value", value = [["left#right" # journal]], expected = "left#rightExpanded" },
    { name = "nested braces keep internal hashes", value = [[{left{middle#right}end} # journal]], expected = "left{middle#right}endExpanded" },
    { name = "escaped quotes keep the hash quoted", value = [=["left\"#right" # journal]=], expected = [=[left\"#rightExpanded]=] },
  })
  :each(function(case)
    T["resolve concatenation"][case.name] = function()
      local dir = u.temp_dir()
      local refs = vim.fs.joinpath(dir, "refs.bib")
      local md = vim.fs.joinpath(dir, "paper.md")
      u.write_file(child, refs, "@string{journal = {Expanded}}\n@article{example, title = " .. case.value .. "}")
      u.write_file(child, md, "---\nbibliography: refs.bib\n---\n\nSee @example.")
      child.lua(string.format("require('bib').setup({ zotero = { database = %q } }); vim.cmd.edit(%q)", vim.fs.joinpath(dir, "missing.sqlite"), md))

      local response = u.lsp_request(child, "textDocument/hover", { line = 4, character = 8 })
      eq(response.err, vim.NIL)
      eq(response.result.contents.value, "# " .. case.expected)
    end
  end)

T["parse"]["missing YAML parser reports the error and deletes its scratch buffer"] = function()
  local refs = open_citation()
  local result = child.lua([[
    local before = #vim.api.nvim_list_bufs()
    local original = vim.treesitter.get_parser
    vim.treesitter.get_parser = function(buf, lang, ...)
      if lang == "yaml" then error("YAML parser unavailable") end
      return original(buf, lang, ...)
    end
    local messages = {}
    vim.notify = function(message) table.insert(messages, message) end
    vim.cmd.write()
    vim.treesitter.get_parser = original
    return { messages = messages, before = before, after = #vim.api.nvim_list_bufs() }
  ]])

  eq(result.after, result.before)
  eq(#result.messages, 1)
  eq(result.messages[1]:find("YAML parser unavailable", 1, true) ~= nil, true)
  eq(u.lsp_request(child, "textDocument/definition", { line = 4, character = 8 }).result.uri, vim.uri_from_fname(refs))
end

T["parse"]["deletes its scratch buffer when buffer setup fails"] = function()
  local refs = open_citation()
  local result = child.lua([[
    local before = #vim.api.nvim_list_bufs()
    local original = vim.api.nvim_buf_set_lines
    vim.api.nvim_buf_set_lines = function(buf, start, stop, strict, lines)
      if lines[1] and lines[1]:find("@article", 1, true) then error("scratch setup failed") end
      return original(buf, start, stop, strict, lines)
    end
    local messages = {}
    vim.notify = function(message) table.insert(messages, message) end
    vim.cmd.write()
    vim.api.nvim_buf_set_lines = original
    return { messages = messages, before = before, after = #vim.api.nvim_list_bufs() }
  ]])

  eq(result.after, result.before)
  eq(#result.messages, 1)
  eq(result.messages[1]:find("scratch setup failed", 1, true) ~= nil, true)
  eq(u.lsp_request(child, "textDocument/definition", { line = 4, character = 8 }).result.uri, vim.uri_from_fname(refs))
end

T["load"]["an unreadable bibliography preserves the previous entries"] = function()
  local dir = u.temp_dir()
  local refs, md = vim.fs.joinpath(dir, "refs.bib"), vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, refs, entry)
  u.write_file(child, md, "---\nbibliography: refs.bib\n---\n\nSee @smith2020.")
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } }); vim.cmd.edit(%q)", vim.fs.joinpath(dir, "missing.sqlite"), md))
  local position = { line = 4, character = 8 }
  eq(u.lsp_request(child, "textDocument/definition", position).result.uri, vim.uri_from_fname(refs))
  local messages = child.lua(string.format(
    [[
      local original = vim.fn.filereadable
      vim.fn.filereadable = function(path)
        if path == %q then return 0 end
        return original(path)
      end
      local messages = {}
      vim.notify = function(message) table.insert(messages, message) end
      vim.cmd.write()
      vim.fn.filereadable = original
      return messages
    ]],
    refs
  ))

  eq(u.lsp_request(child, "textDocument/definition", position).result.uri, vim.uri_from_fname(refs))
  eq(#messages, 1)
  eq(messages[1]:find("cannot read", 1, true) ~= nil, true)
end

T["parse"]["scratch cleanup failure preserves the previous bibliography"] = function()
  local refs = open_citation()
  local result = child.lua([[
    local before = #vim.api.nvim_list_bufs()
    local delete = vim.api.nvim_buf_delete
    vim.api.nvim_buf_delete = function(buf, ...)
      local first = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
      local result = delete(buf, ...)
      if first:find("@article", 1, true) then error("scratch cleanup failure") end
      return result
    end
    local messages = {}
    vim.notify = function(message) table.insert(messages, message) end
    vim.cmd.write()
    vim.api.nvim_buf_delete = delete
    return { messages = messages, before = before, after = #vim.api.nvim_list_bufs() }
  ]])

  eq(result.after, result.before)
  eq(#result.messages, 1)
  eq(result.messages[1]:find("scratch cleanup failure", 1, true) ~= nil, true)
  eq(u.lsp_request(child, "textDocument/definition", { line = 4, character = 8 }).result.uri, vim.uri_from_fname(refs))
end

T["parse"]["scratch cleanup failure does not replace the setup error"] = function()
  local refs = open_citation()
  local result = child.lua([[
    local before = #vim.api.nvim_list_bufs()
    local set_lines, delete = vim.api.nvim_buf_set_lines, vim.api.nvim_buf_delete
    local target
    vim.api.nvim_buf_set_lines = function(buf, start, stop, strict, lines)
      if lines[1] and lines[1]:find("@article", 1, true) then
        target = buf
        error("primary setup failure")
      end
      return set_lines(buf, start, stop, strict, lines)
    end
    vim.api.nvim_buf_delete = function(buf, ...)
      local result = delete(buf, ...)
      if buf == target then error("cleanup failure") end
      return result
    end
    local messages, warnings = {}, {}
    vim.notify = function(message) table.insert(messages, message) end
    vim.lsp.log.warn = function(message) table.insert(warnings, message) end
    vim.cmd.write()
    vim.api.nvim_buf_set_lines, vim.api.nvim_buf_delete = set_lines, delete
    return { messages = messages, warnings = warnings, before = before, after = #vim.api.nvim_list_bufs() }
  ]])

  eq(result.after, result.before)
  eq(#result.messages, 1)
  eq(result.messages[1]:find("primary setup failure", 1, true) ~= nil, true)
  eq(#result.warnings, 1)
  eq(result.warnings[1]:find("cleanup failure", 1, true) ~= nil, true)
  eq(u.lsp_request(child, "textDocument/definition", { line = 4, character = 8 }).result.uri, vim.uri_from_fname(refs))
end

T["parse"]["YAML scratch cleanup preserves the parser error"] = function()
  local refs = open_citation()
  local result = child.lua([[
    local before = #vim.api.nvim_list_bufs()
    local get_parser, delete = vim.treesitter.get_parser, vim.api.nvim_buf_delete
    local target
    vim.treesitter.get_parser = function(buf, lang, ...)
      if lang == "yaml" then
        target = buf
        error("primary YAML failure")
      end
      return get_parser(buf, lang, ...)
    end
    vim.api.nvim_buf_delete = function(buf, ...)
      local result = delete(buf, ...)
      if buf == target then error("YAML cleanup failure") end
      return result
    end
    local messages, warnings = {}, {}
    vim.notify = function(message) table.insert(messages, message) end
    vim.lsp.log.warn = function(message) table.insert(warnings, message) end
    vim.cmd.write()
    vim.treesitter.get_parser, vim.api.nvim_buf_delete = get_parser, delete
    return { messages = messages, warnings = warnings, before = before, after = #vim.api.nvim_list_bufs() }
  ]])

  eq(result.after, result.before)
  eq(#result.messages, 1)
  eq(result.messages[1]:find("primary YAML failure", 1, true) ~= nil, true)
  eq(#result.warnings, 1)
  eq(result.warnings[1]:find("YAML cleanup failure", 1, true) ~= nil, true)
  eq(u.lsp_request(child, "textDocument/definition", { line = 4, character = 8 }).result.uri, vim.uri_from_fname(refs))
end
return T
