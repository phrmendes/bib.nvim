local c = require("bib.constants")
local display_key = require("bib.utils").display_key
local position = require("bib.utils.lsp").position
local citekey = require("bib.utils.lsp").citekey
local citekey_at = require("bib.utils.lsp").citekey_at

---@type table
local lsp = {}

---@type {name: string, stopped: boolean, backend: Backend|nil}
local state = {
	name = "bib_ls",
	stopped = true,
	backend = nil,
}

---@type table
local handlers = {}

---@param _ table
---@param callback BibLspCallback
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

---@param params BibLspParams
---@param callback BibLspCallback
handlers["textDocument/completion"] = function(params, callback)
	vim.schedule(function()
		local lnum, char, bufnr = position(params)

		local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { lnum, char } })

		local skip = { fenced_code_block = true, code_fence_content = true, code_span = true }

		while node do
			if skip[node:type()] then
				callback(nil, { isIncomplete = false, items = {} })
				return
			end

			node = node:parent()
		end

		local word = citekey_at(bufnr, lnum, char, true)

		if not word then
			callback(nil, { isIncomplete = false, items = {} })
			return
		end

		local range = {
			start = { line = lnum, character = char - #word },
			["end"] = { line = lnum, character = char },
		}

		if not state.backend then
			callback(nil, { isIncomplete = false, items = {} })
			return
		end

		local items = vim
			.iter(state.backend.match(word))
			:map(function(entry)
				local label = string.format("%s [%s]", display_key(entry), entry.type)

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

---@param params BibLspCompletionItem
---@param callback BibLspCallback
handlers["completionItem/resolve"] = function(params, callback)
	if not state.backend then
		callback(nil, params)
		return
	end

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

---@param params BibLspParams
---@param callback BibLspCallback
handlers["textDocument/definition"] = function(params, callback)
	if not state.backend then
		callback(nil, nil)
		return
	end

	local found = citekey(params)

	if not found then
		callback(nil, nil)
		return
	end

	local loc = state.backend.definition(found)

	callback(nil, loc)
end

---@param params BibLspParams
---@param callback BibLspCallback
handlers["textDocument/hover"] = function(params, callback)
	if not state.backend then
		callback(nil, nil)
		return
	end

	local found = citekey(params)

	if not found then
		callback(nil, nil)
		return
	end

	local content = state.backend.hover(found)

	if not content then
		callback(nil, nil)
		return
	end

	callback(nil, { contents = { kind = "markdown", value = content } })
end

handlers.notify = {}

handlers.notify["initialized"] = function()
	state.stopped = false
	local zotero = require("bib.backends.zotero")
	if pcall(zotero.load) then state.backend = zotero end

	vim.api.nvim_create_autocmd("BufWinEnter", {
		group = vim.api.nvim_create_augroup("BibConcealInit", { clear = true }),
		callback = function(args)
			if state.backend then require("bib.conceal").setup(args.buf) end
		end,
	})

	vim.api.nvim_exec_autocmds("BufWinEnter", {})
end

---@return BibLspServer
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

---@return Backend|nil
function lsp.backend() return state.backend end

--- Select backend for a buffer: bib first, zotero fallback
---@param bufnr integer
---@return Backend|nil
function lsp.pick(bufnr)
	local bib = require("bib.backends.bib")

	if pcall(bib.load, bufnr) then
		state.backend = bib
		return state.backend
	end

	local zotero = require("bib.backends.zotero")

	if pcall(zotero.load) then state.backend = zotero end

	return state.backend
end

function lsp.attach()
	vim.api.nvim_create_autocmd("LspAttach", {
		pattern = state.name,
		group = vim.api.nvim_create_augroup("BibLspAttach", { clear = true }),
		callback = function(args)
			local bufnr = args.buf

			if not lsp.pick(bufnr) then
				local client = vim.lsp.get_client_by_id(args.data.client_id)
				if client then client:stop() end
				return
			end

			require("bib.conceal").setup(bufnr)

			vim.api.nvim_create_autocmd("BufWritePost", {
				buffer = bufnr,
				group = vim.api.nvim_create_augroup("BibReloadBackend" .. bufnr, { clear = true }),
				callback = function() state.backend.load(bufnr) end,
			})
		end,
	})
end

return lsp
