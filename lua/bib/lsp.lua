local c = require("bib.constants")
local display_key = require("bib.utils").display_key
local position = require("bib.utils.lsp").position
local citekey = require("bib.utils.lsp").citekey
local citekey_at = require("bib.utils.lsp").citekey_at

---@type table
local lsp = {}

---@type {name: string, stopped: boolean, backend: Backend|nil, notified: boolean|nil}
local state = {
	name = "bib_ls",
	stopped = true,
	backend = nil,
}

---@type table
local handlers = {}

--- Try to load a backend if none is active
local function ensure_backend()
	if state.backend then return true end
	local zotero = require("bib.backends.zotero")
	local ok, err = pcall(zotero.load)

	if ok then
		state.backend = zotero
		return true
	end

	vim.lsp.log.warn("[bib.lsp] zotero backend failed: " .. tostring(err))
end

---@param callback BibLspCallback
handlers["initialize"] = function(_, callback)
	callback(nil, {
		capabilities = {
			definitionProvider = true,
			hoverProvider = true,
			codeActionProvider = true,
			executeCommandProvider = { commands = { "bib.open_pdf" } },
			completionProvider = { resolveProvider = true },
		},
	})
end

handlers["shutdown"] = function(_, callback)
	state.stopped = true
	callback(nil, nil)
end

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

		if not ensure_backend() then
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
	if not ensure_backend() then
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
	if not ensure_backend() then
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
	if not ensure_backend() then
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

handlers["textDocument/codeAction"] = function(params, callback)
	if not ensure_backend() then
		callback(nil, nil)
		return
	end

	local key = citekey_at(vim.uri_to_bufnr(params.textDocument.uri), params.range.start.line, params.range.start.character)
	local entry = key and state.backend.get(key)

	if not entry then
		callback(nil, nil)
		return
	end

	callback(nil, require("bib.utils.actions").build(entry, params))
end

handlers["workspace/executeCommand"] = function(params, callback)
	if params.command == "bib.open_pdf" and params.arguments and params.arguments[1] then vim.ui.open(params.arguments[1]) end
	callback(nil, nil)
end

handlers.notify = {}

---@param dispatchers vim.lsp.rpc.Dispatchers
---@return BibLspServer
function lsp.server(dispatchers)
	state.stopped = false
	return {
		request = function(method, params, callback)
			local handler = handlers[method]

			if handler then
				local ok, err = pcall(handler, params, callback)
				if not ok then vim.lsp.log.error("[bib.lsp] handler error (" .. method .. "): " .. tostring(err)) end
				return ok
			end

			callback(nil, nil)
			return true
		end,
		notify = function(method, _)
			if method == "exit" then
				state.stopped = true
				dispatchers.on_exit(0, 15)
				return
			end
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

	if pcall(bib.load, bufnr) and #bib.all() > 0 then
		state.backend = bib
		return state.backend
	end

	local zotero = require("bib.backends.zotero")
	local ok, err = pcall(zotero.load)

	if ok then
		state.backend = zotero
	else
		vim.lsp.log.warn("[bib.lsp] zotero backend failed: " .. tostring(err))
	end

	return state.backend
end

function lsp.attach()
	vim.api.nvim_create_autocmd("LspAttach", {
		group = vim.api.nvim_create_augroup("BibLspAttach", { clear = true }),
		callback = function(args)
			local client = vim.lsp.get_client_by_id(args.data.client_id)
			if not client or client.name ~= state.name then return end

			local bufnr = args.buf

			if not lsp.pick(bufnr) then
				if not state.notified then
					state.notified = true
					vim.notify("[bib.lsp] no backend available, open ~/.local/state/nvim/lsp.log", vim.log.levels.WARN)
				end
				client:stop()
				return
			end

			vim.api.nvim_create_autocmd("BufWritePost", {
				buffer = bufnr,
				group = vim.api.nvim_create_augroup("BibReloadBackend" .. bufnr, { clear = true }),
				callback = function() state.backend.load(bufnr) end,
			})
		end,
	})
end

return lsp
