local test = require("mini.test")
local eq = test.expect.equality

local T = test.new_set()

T["sqlite"] = test.new_set()

T["sqlite"]["can open in-memory database"] = function()
  local db = require("sqlite").new(":memory:")
  ---@cast db sqlite_db
  db:open()
  eq(type(db), "table")
  db:eval("CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)")
  db:insert("test", { value = "hello" })
  local rows = db:eval("SELECT value FROM test")
  eq(type(rows), "table")
  eq(rows[1].value, "hello")
  db:close()
end

return T
