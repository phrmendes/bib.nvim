local patterns = require("bib.patterns")
local find_bib_file = require("bib.utils.backends").find_bib_file
local parse = require("bib.utils.backends").parse

---@type table
local bib = {}

local DEFAULT_BIB = "references.bib"

--- The backend instance from the last `bib.load`. Module-level functions below
--- delegate to it, so existing callers keep working.
---@type table|nil
local current = nil

--- Resolve the .bib path for a buffer, with the default file as fallback.
---@param bufnr integer
---@return string
local function resolve(bufnr)
	local bufname = vim.api.nvim_buf_get_name(bufnr)
	local dir = bufname ~= "" and vim.fn.fnamemodify(bufname, ":p:h") or vim.fn.getcwd()
	return find_bib_file(bufnr) or vim.fn.fnamemodify(dir .. "/" .. DEFAULT_BIB, ":p")
end

--- Build a backend instance with its own entries, so two buffers never share.
---@param state { entries: table<string, BibEntry>, path: string|nil }
---@return table
local function make_backend(state)
	local backend = { path = state.path }

	--- Reload entries from the buffer's .bib file
	---@param bufnr integer
	function backend.load(bufnr)
		state.path = resolve(bufnr)
		backend.path = state.path
		state.entries = parse(state.path) or {}
	end

	--- Get entries whose key starts with a prefix (case-insensitive)
	---@param prefix string
	---@return BibEntry[]
	function backend.match(prefix)
		local lower = prefix:lower()
		return vim.iter(pairs(state.entries)):filter(function(key) return key:lower():find(lower, 1, true) == 1 end):map(function(_, entry) return entry end):totable()
	end

	--- Get a single entry by key
	---@param key string
	---@return BibEntry|nil
	function backend.get(key) return state.entries[key] end

	--- Get all entries
	---@return BibEntry[]
	function backend.all()
		return vim.iter(pairs(state.entries)):map(function(_, e) return e end):totable()
	end

	--- Search entries by substring (case-insensitive, matches key/title/author)
	---@param query string
	---@return BibEntry[]
	function backend.search(query)
		local lower = query:lower()
		return vim
			.iter(pairs(state.entries))
			:filter(function(_, e)
				if e.key:lower():find(lower, 1, true) then return true end
				if e.fields.title and e.fields.title:lower():find(lower, 1, true) then return true end
				if e.fields.author and e.fields.author:lower():find(lower, 1, true) then return true end
				return false
			end)
			:map(function(_, e) return e end)
			:totable()
	end

	--- Get go-to-definition location for a key
	---@param key string
	---@return {uri: string, range: table}|nil
	function backend.definition(key)
		if not state.path then return end

		local entry = state.entries[key]
		if not entry then return end

		return {
			uri = vim.uri_from_fname(state.path),
			range = {
				start = { line = entry.line - 1, character = 0 },
				["end"] = { line = entry.line - 1, character = 0 },
			},
		}
	end

	--- Get hover content for a key
	---@param key string
	---@return string|nil
	function backend.hover(key)
		local entry = state.entries[key]
		if not entry then return end

		local header = {}
		if entry.fields.author then table.insert(header, entry.fields.author) end
		if entry.fields.title then table.insert(header, entry.fields.title) end
		if entry.fields.year then table.insert(header, entry.fields.year) end

		local parts = { "# " .. table.concat(header, " - ") }
		if entry.fields.abstract then
			local abstract = entry.fields.abstract:gsub(patterns.whitespace, " ")
			table.insert(parts, "---\n" .. abstract)
		end

		return table.concat(parts, "\n\n")
	end

	return backend
end

--- Load the .bib backend for a buffer.
--- Each call returns a new instance with its own entries.
---@param bufnr integer
---@return table
function bib.load(bufnr)
	local backend = make_backend({ entries = {}, path = nil })
	backend.load(bufnr)
	current = backend
	return backend
end

--- Get a per-buffer backend without replacing the module-level instance.
---@param bufnr integer
---@return table
function bib.backend(bufnr)
	local backend = make_backend({ entries = {}, path = nil })
	backend.load(bufnr)
	return backend
end

---@param prefix string
---@return BibEntry[]
function bib.match(prefix) return current and current.match(prefix) or {} end

---@param key string
---@return BibEntry|nil
function bib.get(key) return current and current.get(key) end

---@return BibEntry[]
function bib.all() return current and current.all() or {} end

---@param query string
---@return BibEntry[]
function bib.search(query) return current and current.search(query) or {} end

---@param key string
---@return {uri: string, range: table}|nil
function bib.definition(key) return current and current.definition(key) end

---@param key string
---@return string|nil
function bib.hover(key) return current and current.hover(key) end

return bib
