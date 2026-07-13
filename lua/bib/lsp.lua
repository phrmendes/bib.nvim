local backend = require("bib.backends.bib")
local utils = require("bib.utils")

local lsp = {}

local server_state = {
	name = "bib_ls",
	stopped = true,
}

--- Check if cursor is in a valid completion region using tree-sitter
---@param bufnr integer
---@return boolean
local function in_completion_region(bufnr)
	local cursor = vim.api.nvim_win_get_cursor(0)
	local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { cursor[1] - 1, cursor[2] } })
	if not node then return true end

	while node do
		local t = node:type()
		if t == "fenced_code_block" or t == "code_fence_content" or t == "code_span" then return false end
		node = node:parent()
	end

	return true
end

--- Build a completion label from an entry
---@param entry BibEntry
---@return string
local function completion_label(entry)
	local label = string.format("%s [%s]", entry.key, entry.type)
	if entry.fields.author then label = label .. " " .. entry.fields.author end
	if entry.fields.year then label = label .. " (" .. entry.fields.year .. ")" end
	if #label > 80 then label = label:sub(1, 77) .. "..." end
	return label
end

--- Build LSP completion items from matched entries
---@param matches BibEntry[]
---@param lnum integer
---@param char integer
---@return table[]
local function completion_items(matches, lnum, char)
	local range = {
		start = { line = lnum, character = char - 1 },
		["end"] = { line = lnum, character = char },
	}
	return vim
		.iter(matches)
		:map(function(entry)
			return {
				label = completion_label(entry),
				kind = vim.lsp.protocol.CompletionItemKind.Reference,
				textEdit = { newText = entry.key, range = range },
			}
		end)
		:totable()
end

--- Completion handler
---@param callback function
---@param lnum integer
---@param char integer
local function handle_completion(callback, lnum, char, bufnr)
	if not in_completion_region(bufnr) then
		callback(nil, { isIncomplete = false, items = {} })
		return
	end

	local word = utils.key_at(bufnr, lnum, char, true)

	if not word then
		callback(nil, { isIncomplete = false, items = {} })
		return
	end

	local items = completion_items(backend.match(word), lnum, char)
	callback(nil, { isIncomplete = false, items = items })
end

--- Completion item resolve handler
---@param params table
---@param callback function
local function handle_completion_resolve(params, callback)
	local key = params.textEdit.newText
	local entry = backend.get(key)

	if not entry then
		callback(nil, params)
		return
	end

	params.detail = entry.type
	local hover = backend.hover(key)
	if hover then params.documentation = { kind = "markdown", value = hover } end

	callback(nil, params)
end

--- Definition handler
---@param params table
---@param callback function
local function handle_definition(params, callback)
	local lnum = params.position.line
	local char = params.position.character
	local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
	local key = utils.key_at(bufnr, lnum, char)

	if not key or key == "" then
		callback(nil, { result = nil })
		return
	end

	local loc = backend.definition(key)
	callback(nil, { result = loc })
end

--- Hover handler
---@param params table
---@param callback function
local function handle_hover(params, callback)
	local lnum = params.position.line
	local char = params.position.character
	local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
	local key = utils.key_at(bufnr, lnum, char)

	if not key or key == "" then
		callback(nil, { result = nil })
		return
	end

	local content = backend.hover(key)

	if not content then
		callback(nil, nil)
		return
	end

	callback(nil, { contents = { kind = "markdown", value = content } })
end

local handlers = {
	["initialize"] = function(_, callback)
		callback(nil, {
			capabilities = {
				textDocument = { completion = { completionItem = { snippetSupport = false } } },
				definitionProvider = true,
				hoverProvider = true,
				completionProvider = { resolveProvider = true },
			},
		})
	end,
	["shutdown"] = function() server_state.stopped = true end,
	["textDocument/completion"] = function(params, callback)
		vim.schedule(function() handle_completion(callback, params.position.line, params.position.character, vim.uri_to_bufnr(params.textDocument.uri)) end)
	end,
	["completionItem/resolve"] = handle_completion_resolve,
	["textDocument/definition"] = handle_definition,
	["textDocument/hover"] = handle_hover,
}

---@param method string
---@param params table
---@param callback function
local function lsp_request(method, params, callback, _)
	local handler = handlers[method]

	if handler then
		handler(params, callback)
		return
	end

	if callback then callback(nil, nil) end
end

local notify_handlers = {
	["initialized"] = function() server_state.stopped = false end,
}

---@param method string
---@param _ table
local function lsp_notify(method, _)
	local handler = notify_handlers[method]
	if handler then handler() end
end

--- LSP server entry point
---@return table
function lsp.server()
	return {
		request = lsp_request,
		notify = lsp_notify,
		is_closing = function() return server_state.stopped end,
		terminate = function() server_state.stopped = true end,
	}
end

--- Start the LSP server for the current buffer
---@param bufnr integer
function lsp.start(bufnr)
	if not backend.load(bufnr) then return end

	vim.lsp.enable(server_state.name)

	vim.api.nvim_create_autocmd("BufWritePost", {
		buffer = bufnr,
		callback = function() backend.load(bufnr) end,
		group = vim.api.nvim_create_augroup("BibLSP", { clear = true }),
		desc = "Refresh bib entries when buffer is saved",
	})
end

return lsp
