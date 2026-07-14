local test = require("mini.test")
local eq = test.expect.equality

local utils = {}

--- Create a temporary directory for tests
---@return string
utils.temp_dir = function()
	local id = string.format("%d_%d", vim.uv.now(), math.random(1000, 9999))
	local dir = vim.fs.joinpath("/tmp", "bib.nvim", "test_" .. id)
	vim.fn.mkdir(dir, "p")
	return dir
end

--- Create a child Neovim process with test hooks
---@return table child
---@return table T
utils.new_child_set = function()
	local child = test.new_child_neovim()
	local T = test.new_set({
		hooks = {
			pre_case = function() child.restart({ "--noplugin", "-u", "scripts/init.lua" }) end,
			post_case = function()
				local temp_dirs = child.lua_get("vim.fn.glob('/tmp/bib.nvim/test_*', 0, 1)")
				vim.iter(temp_dirs):each(function(dir) child.lua(string.format("vim.fn.delete(%q, 'rf')", dir)) end)
			end,
			post_once = function() child.stop() end,
		},
	})
	return child, T
end

--- Write a file in a child process
---@param child MiniTest.child
---@param path string
---@param content string
utils.write_file = function(child, path, content)
	local lines = vim.iter(vim.split(content, "\n")):map(function(line) return string.format("%q", line) end):totable()
	child.lua(string.format("vim.fn.writefile({ %s }, %q)", table.concat(lines, ", "), path))
end

--- Read a file in a child process
---@param child MiniTest.child
---@param path string
---@return string[]
utils.read_file = function(child, path) return child.lua_get(string.format("vim.fn.readfile(%q)", path)) end

--- Assert file exists
---@param child MiniTest.child
---@param path string
utils.assert_file_exists = function(child, path) eq(child.lua_get(string.format("vim.uv.fs_stat(%q) ~= nil", path)), true) end

--- Set up a bib backend in a child process with a .bib file and markdown buffer
---@param child MiniTest.child
---@param bib_content string
---@return string dir
utils.setup_bib = function(child, bib_content)
	local dir = utils.temp_dir()
	utils.write_file(child, vim.fs.joinpath(dir, "refs.bib"), bib_content)
	utils.write_file(child, vim.fs.joinpath(dir, "paper.md"), "---\nbibliography: refs.bib\n---\n")
	child.lua(string.format("vim.cmd.edit(%q)", vim.fs.joinpath(dir, "paper.md")))
	child.lua("require('bib.backends.bib').load(vim.api.nvim_get_current_buf())")
	return dir
end

--- Set up a Zotero test database in a child process
---@param child MiniTest.child
---@param dir string
---@return string db_path
utils.setup_zotero_db = function(child, dir)
	local db_path = vim.fs.joinpath(dir, "zotero.sqlite")
	local sql = string.format(
		[[
		local sqlite = require("sqlite")
		local db = sqlite.new("%s"); db:open()
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
		db:eval("INSERT INTO itemTypes VALUES (1, 'journalArticle')")
		db:eval("INSERT INTO fields VALUES (1, 'title'), (2, 'abstractNote'), (6, 'date'), (9, 'citationKey')")
		db:eval("INSERT INTO itemDataValues VALUES (1, 'Test Title'), (2, 'An abstract.'), (3, '2020'), (4, 'smith2020')")
		db:eval("INSERT INTO items VALUES (1, 1, 'ABC123', 1)")
		db:eval("INSERT INTO itemData VALUES (1, 1, 1), (1, 2, 2), (1, 6, 3), (1, 9, 4)")
		db:eval("INSERT INTO creators VALUES (1, 'Smith', 'John', 0)")
		db:eval("INSERT INTO creatorTypes VALUES (1, 'author')")
		db:eval("INSERT INTO itemCreators VALUES (1, 1, 1, 0)")
		db:eval("INSERT INTO itemNotes VALUES (1, 1, 'A note about stuff.', 'Note 1')")
		db:eval("INSERT INTO itemAttachments VALUES (1, 1, '/tmp/test.pdf', 'application/pdf')")
		db:close()
	]],
		db_path
	)
	child.lua(sql)
	return db_path
end

return utils
