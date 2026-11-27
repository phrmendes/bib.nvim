local test = require("mini.test")
local u = dofile("tests/utils.lua")
local eq = test.expect.equality

local child, T = u.new_child_set()
local entry = "@article{selected, title = {Selected}}"

T["markdown"] = test.new_set()

vim
  .iter({
    { name = "frontmatter selects its bibliography", content = "---\nbibliography: refs.bib\n---\n", expected = "refs.bib" },
    { name = "marker selects its bibliography", content = "# Paper\n", marker = '{"bibliography":"refs.bib"}', expected = "refs.bib" },
    { name = "marker works when frontmatter has no bibliography", content = "---\ntitle: Paper\n---\n", marker = '{"bibliography":"refs.bib"}', expected = "refs.bib" },
    { name = "default bibliography works without a declaration", content = "# Paper\n", expected = "references.bib" },
    {
      name = "frontmatter takes precedence over the marker",
      content = "---\nbibliography: yaml.bib\n---\n",
      marker = '{"bibliography":"json.bib"}',
      expected = "yaml.bib",
    },
  })
  :each(function(case)
    T["markdown"][case.name] = function()
      local dir = u.temp_dir()
      local md = vim.fs.joinpath(dir, "paper.md")
      local content = case.content .. "\nSee @selected."
      vim.iter({ "refs.bib", "references.bib", "yaml.bib", "json.bib" }):each(function(name) u.write_file(child, vim.fs.joinpath(dir, name), entry) end)
      if case.marker then u.write_file(child, vim.fs.joinpath(dir, ".bib.json"), case.marker) end
      u.write_file(child, md, content)
      child.lua(string.format("require('bib').setup({ zotero = { database = %q } }); vim.cmd.edit(%q)", vim.fs.joinpath(dir, "missing.sqlite"), md))

      local response = u.lsp_request(child, "textDocument/definition", { line = #vim.split(content, "\n") - 1, character = 8 })
      eq(response.err, vim.NIL)
      eq(response.result.uri, vim.uri_from_fname(vim.fs.joinpath(dir, case.expected)))
    end
  end)

T["markdown"]["uses an absolute bibliography path"] = function()
  local dir = u.temp_dir()
  local refs = vim.fs.joinpath(dir, "refs.bib")
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, refs, entry)
  u.write_file(child, md, "---\nbibliography: " .. refs .. "\n---\n\nSee @selected.")
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } }); vim.cmd.edit(%q)", vim.fs.joinpath(dir, "missing.sqlite"), md))

  local response = u.lsp_request(child, "textDocument/definition", { line = 4, character = 8 })
  eq(response.err, vim.NIL)
  eq(response.result.uri, vim.uri_from_fname(refs))
end

T["markdown"]["finds a marker in an ancestor directory"] = function()
  local dir = u.temp_dir()
  local nested = vim.fs.joinpath(dir, "chapters")
  vim.fn.mkdir(nested, "p")
  local md = vim.fs.joinpath(nested, "paper.md")
  local refs = vim.fs.joinpath(dir, "refs.bib")
  u.write_file(child, refs, entry)
  u.write_file(child, vim.fs.joinpath(dir, ".bib.json"), '{"bibliography":"refs.bib"}')
  u.write_file(child, md, "# Paper\n\nSee @selected.")
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } }); vim.cmd.edit(%q)", vim.fs.joinpath(dir, "missing.sqlite"), md))

  local response = u.lsp_request(child, "textDocument/definition", { line = 2, character = 8 })
  eq(response.err, vim.NIL)
  eq(response.result.uri, vim.uri_from_fname(refs))
end

T["latex"] = test.new_set()

vim
  .iter({
    { name = "bibliography selects a bib file", declaration = "\\bibliography{refs}" },
    { name = "addbibresource keeps its extension", declaration = "\\addbibresource{refs.bib}" },
    { name = "first bibliography declaration wins", declaration = "\\bibliography{refs}\n\\bibliography{other}" },
  })
  :each(function(case)
    T["latex"][case.name] = function()
      local dir = u.temp_dir()
      local tex = vim.fs.joinpath(dir, "paper.tex")
      local refs = vim.fs.joinpath(dir, "refs.bib")
      u.write_file(child, refs, entry)
      u.write_file(child, vim.fs.joinpath(dir, "other.bib"), entry)
      local lines = vim.split(case.declaration, "\n")
      local citation_line = #lines + 1
      u.write_file(child, tex, case.declaration .. "\n\\begin{document}\nSee \\cite{selected}.\n\\end{document}")
      child.lua(string.format("require('bib').setup({ zotero = { database = %q } }); vim.cmd.edit(%q)", vim.fs.joinpath(dir, "missing.sqlite"), tex))

      local response = u.lsp_request(child, "textDocument/definition", { line = citation_line, character = 13 })
      eq(response.err, vim.NIL)
      eq(response.result.uri, vim.uri_from_fname(refs))
    end
  end)

T["latex"]["preserves an open modified root document"] = function()
  local dir = u.temp_dir()
  local root = vim.fs.joinpath(dir, "root.tex")
  local chapter = vim.fs.joinpath(dir, "chapter.tex")
  local refs = vim.fs.joinpath(dir, "refs.bib")
  u.write_file(child, refs, entry)
  u.write_file(child, root, "\\documentclass{article}\n\\bibliography{refs}\n")
  u.write_file(child, chapter, "% !TeX root = root.tex\n\\begin{document}\nSee \\cite{selected}.\n\\end{document}")
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } }); vim.cmd.edit(%q)", vim.fs.joinpath(dir, "missing.sqlite"), root))
  local root_buf = child.lua_get("vim.api.nvim_get_current_buf()")
  child.api.nvim_buf_set_lines(root_buf, -1, -1, false, { "% unsaved" })
  child.lua(string.format("vim.cmd.edit(%q)", chapter))

  local response = u.lsp_request(child, "textDocument/definition", { line = 2, character = 13 })
  eq(response.err, vim.NIL)
  eq(response.result.uri, vim.uri_from_fname(refs))
  eq(child.api.nvim_buf_is_valid(root_buf), true)
  eq(child.lua_get(string.format("vim.bo[%d].modified", root_buf)), true)
  eq(vim.list_contains(child.api.nvim_buf_get_lines(root_buf, 0, -1, false), "% unsaved"), true)
end

T["latex"]["reports query iteration failures through the command"] = function()
  local dir = u.temp_dir()
  local tex = vim.fs.joinpath(dir, "paper.tex")
  u.write_file(child, vim.fs.joinpath(dir, "refs.bib"), entry)
  u.write_file(child, tex, "\\bibliography{refs}\n\\begin{document}\nSee \\cite{selected}.\n\\end{document}")
  local result = child.lua(string.format(
    [[
    local parse = vim.treesitter.query.parse
    vim.treesitter.query.parse = function(lang, text)
      local query = parse(lang, text)
      if lang == 'latex' and text:find('bibtex_include', 1, true) then
        query.iter_matches = function() error('iteration failed') end
      end
      return query
    end
    local messages, warnings = {}, {}
    vim.notify = function(message) table.insert(messages, message) end
    vim.lsp.log.warn = function(message) table.insert(warnings, message) end
    require('bib').setup({ zotero = { database = %q } })
    vim.cmd.edit(%q)
    vim.cmd('Bib')
    assert(vim.wait(3000, function()
      return vim.iter(messages):any(function(message) return message == 'No entries found' end)
    end))
    vim.treesitter.query.parse = parse
    return { messages = messages, warnings = warnings }
  ]],
    vim.fs.joinpath(dir, "missing.sqlite"),
    tex
  ))

  eq(vim.list_contains(result.messages, "No entries found"), true)
  eq(vim.iter(result.warnings):any(function(message) return message:find("iteration failed", 1, true) ~= nil end), true)
end

T["markdown"]["does not require the LaTeX parser"] = function()
  local dir = u.temp_dir()
  local md = vim.fs.joinpath(dir, "paper.md")
  local refs = vim.fs.joinpath(dir, "refs.bib")
  u.write_file(child, refs, entry)
  u.write_file(child, md, "---\nbibliography: refs.bib\n---\n\nSee @selected.")
  child.lua(string.format(
    [[
    _G.original_query_parse = vim.treesitter.query.parse
    vim.treesitter.query.parse = function(lang, query)
      if lang == 'latex' then error('LaTeX parser unavailable') end
      return _G.original_query_parse(lang, query)
    end
    require('bib').setup({ zotero = { database = %q } })
    vim.cmd.edit(%q)
  ]],
    vim.fs.joinpath(dir, "missing.sqlite"),
    md
  ))

  local response = u.lsp_request(child, "textDocument/definition", { line = 4, character = 8 })
  child.lua("vim.treesitter.query.parse = _G.original_query_parse; _G.original_query_parse = nil")
  eq(response.err, vim.NIL)
  eq(response.result.uri, vim.uri_from_fname(refs))
end

return T
