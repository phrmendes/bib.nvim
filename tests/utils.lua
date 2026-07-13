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

return utils
