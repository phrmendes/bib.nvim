local bib = require("bib.backends.bib")
local c = require("bib.constants")
local u = require("bib.utils")
local zotero = require("bib.backends.zotero")

local lsp = {}

---@type {name: string, stopped: boolean, backend: Backend}
local state = {
	name = "bib_ls",
	stopped = true,
	backend = bib,
}

--- Pick the best backend for a buffer (bib first, zotero fallback)
---@param bufnr integer
function lsp.pick(bufnr)
	vim.iter({ bib, zotero }):find(function(backend)
		local ok, err = pcall(backend.load, bufnr)

		if ok then
			state.backend = backend
			return true
		end

		vim.lsp.log.warn(err)
	end)
end

local handlers = {}

handlers["initialize"] = function(_, callback)
	callback(nil, {
		capabilities = {
			textDocument = { completion = { completionItem = { snippetSupport = false } } },
			definitionProvider = true,
			hoverProvider = true,
			completionProvider = { resolveProvider = true },
		},
	})
end

handlers["shutdown"] = function() state.stopped = true end

handlers["textDocument/completion"] = function(params, callback)
	vim.schedule(function()
		local lnum, char, bufnr = u.lsp.pos(params)

		local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { lnum, char } })

		while node do
			local t = node:type()

			if t == "fenced_code_block" or t == "code_fence_content" or t == "code_span" then
				callback(nil, { isIncomplete = false, items = {} })
				return
			end

			node = node:parent()
		end

		local word = u.lsp.key_at(bufnr, lnum, char, true)

		if not word then
			callback(nil, { isIncomplete = false, items = {} })
			return
		end

		local range = {
			start = { line = lnum, character = char - #word },
			["end"] = { line = lnum, character = char },
		}

		local items = vim
			.iter(state.backend.match(word))
			:map(function(entry)
				local label = string.format("%s [%s]", u.display_key(entry), entry.type)

				if entry.fields.author then label = label .. " " .. entry.fields.author end

				if entry.fields.year then label = label .. " (" .. entry.fields.year .. ")" end

				if #label > c.COMPLETION_MAX_LABEL then label = label:sub(1, c.COMPLETION_MAX_LABEL - 3) .. "..." end

				return {
					label = label,
					kind = vim.lsp.protocol.CompletionItemKind.Reference,
					textEdit = { newText = entry.key, range = range },
				}
			end)
			:totable()

		callback(nil, { isIncomplete = false, items = items })
	end)
end

handlers["completionItem/resolve"] = function(params, callback)
	local key = params.textEdit.newText
	local entry = state.backend.get(key)

	if not entry then
		callback(nil, params)
		return
	end

	params.detail = entry.type

	local content = state.backend.hover(key)

	if content then params.documentation = { kind = "markdown", value = content } end

	callback(nil, params)
end

handlers["textDocument/definition"] = function(params, callback)
	local key = u.lsp.key(params)

	if not key then
		callback(nil, { result = nil })
		return
	end

	local loc = state.backend.definition(key)
	callback(nil, { result = loc })
end

handlers["textDocument/hover"] = function(params, callback)
	local key = u.lsp.key(params)

	if not key then
		callback(nil, { result = nil })
		return
	end

	local content = state.backend.hover(key)

	if not content then
		callback(nil, nil)
		return
	end

	callback(nil, { contents = { kind = "markdown", value = content } })
end

handlers.notify = {}

handlers.notify["initialized"] = function() state.stopped = false end

--- LSP server entry point
---@return {request: fun(method: string, params: table, callback: function, _: table?), notify: fun(method: string, _: table?), is_closing: fun(): boolean, terminate: function}
function lsp.server()
	return {
		request = function(method, params, callback, _)
			local handler = handlers[method]

			if handler then
				handler(params, callback)
				return
			end

			callback(nil, nil)
		end,
		notify = function(method, _)
			local handler = handlers.notify[method]
			if handler then handler() end
		end,
		is_closing = function() return state.stopped end,
		terminate = function() state.stopped = true end,
	}
end

--- Start the LSP server for the current buffer
---@param bufnr integer
function lsp.start(bufnr)
	lsp.pick(bufnr)

	if not state.backend then return end

	vim.lsp.enable(state.name)

	require("bib.conceal").setup(bufnr)

	vim.api.nvim_create_autocmd("BufWritePost", {
		buffer = bufnr,
		callback = function() state.backend.load(bufnr) end,
		group = vim.api.nvim_create_augroup("BibLSP", { clear = true }),
		desc = "Refresh bib entries when buffer is saved",
	})
end

return lsp
