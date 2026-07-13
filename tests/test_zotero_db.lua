local test = require("mini.test")
local tu = dofile("tests/utils.lua")
local eq = test.expect.equality

local child, T = tu.new_child_set()

T["find_zotero_db"] = test.new_set()

vim.iter({
  { name = "returns default path when no config", override = nil, expected = vim.fs.joinpath(vim.env.HOME, "Zotero", "zotero.sqlite") },
  { name = "returns override when configured", override = "/custom/zotero.sqlite", expected = "/custom/zotero.sqlite" },
}):each(function(c)
  T["find_zotero_db"][c.name] = function()
    if c.override then
      child.lua(string.format("require('bib.config').setup({ zotero = { database = %q } })", c.override))
    end
    eq(child.lua_get("require('bib.utils').find_zotero_db()"), c.expected)
  end
end)

return T
