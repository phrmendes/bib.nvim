---@type table
local ts = {}

--- Load a tree-sitter query from a .scm file on the runtimepath
---@param lang string Tree-sitter language
---@param name string Query file name without extension
---@return vim.treesitter.Query
function ts.load(lang, name)
	local path = "queries/" .. lang .. "/" .. name .. ".scm"
	local files = vim.api.nvim_get_runtime_file(path, false)
	if #files == 0 then error("query not found: " .. path) end
	local content = table.concat(vim.fn.readfile(files[1]), "\n")
	return vim.treesitter.query.parse(lang, content)
end

--- Build reverse lookup: capture name -> capture ID
---@param q vim.treesitter.Query
---@return table<string, integer>
function ts.capture_ids(q)
	return vim.iter(pairs(q.captures)):fold({}, function(ids, id, name)
		ids[name] = id
		return ids
	end)
end

--- Run a tree-sitter query and fold results into an accumulator
---@generic T
---@param q vim.treesitter.Query
---@param root TSNode
---@param buf integer
---@param initial T
---@param fn fun(acc: T, match: table, ids: table): T
---@return T
function ts.fold(q, root, buf, initial, fn)
	local ids = ts.capture_ids(q)
	local matches = q:iter_matches(root, buf, 0, -1)
	return vim.iter(matches):fold(initial, function(acc, _, match) return fn(acc, match, ids) end)
end

return ts
