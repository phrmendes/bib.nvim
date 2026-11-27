local test = require("mini.test")
local u = dofile("tests/utils.lua")
local eq = test.expect.equality

local child, T = u.new_child_set()

T["conceal"] = test.new_set()

--- Create a document and collect citation marks.
---@param content string
---@return table[]
local function setup_conceal(content)
  local dir = u.temp_dir()
  local md = vim.fs.joinpath(dir, "paper.md")
  u.write_file(child, md, content)
  child.lua(string.format("require('bib').setup({ zotero = { database = %q } })", vim.fs.joinpath(dir, "missing.sqlite")))
  child.lua(string.format("vim.cmd.edit(%q)", md))
  return child.lua([[
    local ns = vim.api.nvim_get_namespaces()["bib_conceal"]
    local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
    table.sort(marks, function(a, b) return a[3] < b[3] end)
    return marks
  ]])
end

--- Return a mark start column.
---@param marks table[]
---@param i integer
---@return integer
local function col(marks, i) return marks[i][3] end

--- Return a mark end column.
---@param marks table[]
---@param i integer
---@return integer|nil
local function end_col(marks, i) return marks[i][4].end_col end

--- Return a mark highlight group.
---@param marks table[]
---@param i integer
---@return string|nil
local function hl(marks, i) return marks[i][4].hl_group end

--- Return a mark conceal value.
---@param marks table[]
---@param i integer
---@return string|nil
local function conceal(marks, i) return marks[i][4].conceal end

T["conceal"]["extmarks placed at correct 0-indexed columns"] = function()
  local extmarks = setup_conceal("see @ABC123#smith2020 for details")

  eq(#extmarks, 3)
  eq(col(extmarks, 1), 4)
  eq(hl(extmarks, 1), "BibCitePrefix")
  eq(col(extmarks, 2), 5)
  eq(end_col(extmarks, 2), 12)
  eq(conceal(extmarks, 2), "")
  eq(col(extmarks, 3), 12)
  eq(end_col(extmarks, 3), 21)
  eq(hl(extmarks, 3), "BibCiteKey")
end

T["conceal"]["skips citekey extmark when no citekey follows prefix"] = function()
  local extmarks = setup_conceal("see @ABC123# and more text")

  eq(#extmarks, 2)
  eq(col(extmarks, 1), 4)
  eq(hl(extmarks, 1), "BibCitePrefix")
  eq(col(extmarks, 2), 5)
  eq(end_col(extmarks, 2), 12)
  eq(conceal(extmarks, 2), "")
end

T["conceal"]["handles multiple prefixes on one line"] = function()
  local extmarks = setup_conceal("see @ABC123#smith2020 and @DEF456#jones2021")

  eq(#extmarks, 6)

  local at1, prefix1_end, citekey1_start, citekey1_end = 4, 12, 12, 21

  eq(col(extmarks, 1), at1)
  eq(col(extmarks, 2), at1 + 1)
  eq(end_col(extmarks, 2), prefix1_end)
  eq(conceal(extmarks, 2), "")
  eq(col(extmarks, 3), citekey1_start)
  eq(end_col(extmarks, 3), citekey1_end)

  local at2, prefix2_end, citekey2_start, citekey2_end = 26, 34, 34, 43

  eq(col(extmarks, 4), at2)
  eq(col(extmarks, 5), at2 + 1)
  eq(end_col(extmarks, 5), prefix2_end)
  eq(conceal(extmarks, 5), "")
  eq(col(extmarks, 6), citekey2_start)
  eq(end_col(extmarks, 6), citekey2_end)
end

T["conceal"]["extmarks update after editing a citation"] = function()
  setup_conceal("see @ABC123#smith2020 for details")
  child.type_keys("gg0", "C", "see @ABC123#jones2021long for details", "<Esc>")
  child.lua([[
    local ns = vim.api.nvim_get_namespaces().bib_conceal
    assert(vim.wait(3000, function()
      local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
      return #marks == 3 and marks[3][4].end_col == 25
    end))
  ]])

  local extmarks = child.lua([[
		local ns = vim.api.nvim_get_namespaces()["bib_conceal"]
		local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
		table.sort(marks, function(a, b) return a[3] < b[3] end)
		return marks
	]])

  eq(#extmarks, 3)
  eq(col(extmarks, 1), 4)
  eq(col(extmarks, 2), 5)
  eq(conceal(extmarks, 2), "")
  eq(col(extmarks, 3), 12)
  eq(end_col(extmarks, 3), 25)
  eq(hl(extmarks, 3), "BibCiteKey")
end

T["conceal"]["extmarks persist after BufWritePost"] = function()
  setup_conceal("see @ABC123#smith2020 for details")

  child.lua("vim.cmd.write()")

  local marks = child.lua([[
		local ns = vim.api.nvim_get_namespaces()["bib_conceal"]
		local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
		table.sort(marks, function(a, b) return a[3] < b[3] end)
		return marks
	]])

  eq(#marks, 3)
  eq(hl(marks, 3), "BibCiteKey")
end

T["conceal"]["skips code fences"] = function()
  local extmarks = setup_conceal("```markdown\n@ABC123#smith2020\n```")

  eq(#extmarks, 0)
end

T["conceal"]["skips inline code spans"] = function()
  local extmarks = setup_conceal("text `@ABC123#smith2020` inline")

  eq(#extmarks, 0)
end

T["conceal"]["marks citations outside multiple inline code spans"] = function()
  local line = "@alpha `@ignored` @beta ``@also_ignored`` @gamma"
  local extmarks = setup_conceal(line)
  local starts = vim.iter({ "@alpha", "@beta", "@gamma" }):map(function(citation) return line:find(citation, 1, true) - 1 end):totable()

  eq(#extmarks, 6)
  eq(col(extmarks, 1), starts[1])
  eq(col(extmarks, 3), starts[2])
  eq(col(extmarks, 5), starts[3])
end

vim.iter({ "throws", "returns nil" }):each(function(failure)
  T["conceal"]["falls back when the host Tree-sitter lookup " .. failure] = function()
    local dir = u.temp_dir()
    local md = vim.fs.joinpath(dir, "paper.md")
    u.write_file(child, md, "```markdown\n@hidden\n```\n\n@visible")
    local marks = child.lua(string.format(
      [[
      require('bib').setup({ zotero = { database = %q } })
      local original = vim.treesitter.get_node
      vim.treesitter.get_node = function(opts)
        if opts.ignore_injections then
          if %q == 'throws' then error('first lookup failed') end
          return nil
        end
        return original(opts)
      end
      vim.cmd.edit(%q)
      vim.treesitter.get_node = original
      local namespace = vim.api.nvim_get_namespaces().bib_conceal
      return vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, {})
    ]],
      vim.fs.joinpath(dir, "missing.sqlite"),
      failure,
      md
    ))

    eq(#marks, 2)
    eq(marks[1][2], 4)
    eq(marks[2][2], 4)
  end
end)

T["conceal"]["skips email addresses"] = function()
  local extmarks = setup_conceal("write to user@example.com today")

  eq(#extmarks, 0)
end

T["conceal"]["plain @citekey gets prefix and key marks"] = function()
  local extmarks = setup_conceal("see @smith2020 for details")

  eq(#extmarks, 2)
  eq(col(extmarks, 1), 4)
  eq(hl(extmarks, 1), "BibCitePrefix")
  eq(col(extmarks, 2), 5)
  eq(end_col(extmarks, 2), 14)
  eq(hl(extmarks, 2), "BibCiteKey")
end

T["conceal"]["ignores unconfigured filetypes"] = function()
  local dir = u.temp_dir()
  local path = vim.fs.joinpath(dir, "paper.py")
  u.write_file(child, path, "# see @decorator for details")
  local result = child.lua(string.format(
    [[
    require('bib').setup({ zotero = { database = %q } })
    vim.cmd.edit(%q)
    local namespace = vim.api.nvim_get_namespaces().bib_conceal
    return { filetype = vim.bo.filetype, marks = vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, {}) }
  ]],
    vim.fs.joinpath(dir, "missing.sqlite"),
    path
  ))

  eq(result.filetype, "python")
  eq(result.marks, {})
end

T["conceal"]["sets conceallevel when opening a document"] = function()
  setup_conceal("see @smith2020 for details")
  eq(child.lua_get("vim.wo.conceallevel"), 2)
end

return T
