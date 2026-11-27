local c = require("bib.constants")
local display_key = require("bib.utils").display_key
local position = require("bib.utils.lsp").position
local citekey = require("bib.utils.lsp").citekey
local citekey_at = require("bib.utils.lsp").citekey_at

---@type table
local lsp = {}

---@type {name: string, stopped: boolean, backends: table<integer, Backend>, notified: boolean|nil}
local state = {
  name = "bib_ls",
  stopped = true,
  backends = {},
}

---@type table
local handlers = {}

--- Return the backend for a buffer.
---@param bufnr integer Buffer handle.
---@return Backend|nil backend Buffer backend, or nil if unset.
---@private
local function backend_for(bufnr) return state.backends[bufnr] end

--- Store the backend for a buffer.
---@param bufnr integer Buffer handle.
---@param backend Backend Backend to associate with the buffer.
---@private
local function set_backend(bufnr, backend) state.backends[bufnr] = backend end

--- Load the Zotero backend when the buffer has no backend yet.
---@param bufnr integer Buffer handle.
---@return Backend|nil backend Existing or loaded backend, or nil on failure.
---@return string|nil error Backend load error, or nil on success.
---@private
local function ensure_backend(bufnr)
  local existing = backend_for(bufnr)
  if existing then return existing end

  local zotero = require("bib.backends.zotero")
  local err = zotero:load()

  if err == nil then
    set_backend(bufnr, zotero)
    return zotero
  end

  vim.lsp.log.warn("[bib.lsp] zotero backend failed: " .. tostring(err))
  return nil, err
end

--- Return the server capabilities.
---@param _ lsp.InitializeParams Unused initialization parameters.
---@param callback BibLspCallback Receives the server capabilities.
---@private
handlers["initialize"] = function(_, callback)
  callback(nil, {
    capabilities = {
      positionEncoding = "utf-8",
      definitionProvider = true,
      hoverProvider = true,
      codeActionProvider = true,
      executeCommandProvider = { commands = { "bib.open_pdf" } },
      completionProvider = { resolveProvider = true },
    },
  })
end

--- Stop the server.
---@param _ any Unused shutdown parameters.
---@param callback BibLspCallback Receives the shutdown response.
---@private
handlers["shutdown"] = function(_, callback)
  state.stopped = true
  callback(nil, nil)
end

--- Complete citation keys at the cursor.
---@param params BibLspParams Document position for completion.
---@param callback BibLspCallback Receives completion items or an LSP error.
---@private
handlers["textDocument/completion"] = function(params, callback)
  vim.schedule(function()
    local ok, handler_err = pcall(function()
      local lnum, char, bufnr = position(params)

      local lang = vim.bo[bufnr].filetype == "tex" and "latex" or "markdown"
      local node = vim.treesitter.get_node({ bufnr = bufnr, lang = lang, pos = { lnum, char }, ignore_injections = false })

      local skip = { fenced_code_block = true, code_fence_content = true, code_span = true }

      while node do
        if skip[node:type()] then
          callback(nil, { isIncomplete = false, items = {} })
          return
        end

        node = node:parent()
      end

      local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1] or ""
      local cursor = char + 1
      for _, span in ipairs(require("bib.utils.conceal").inline_code_ranges(line)) do
        if cursor >= span.s and cursor <= span.e then
          callback(nil, { isIncomplete = false, items = {} })
          return
        end
      end

      local word, err = citekey_at(bufnr, lnum, char, true)
      if err ~= nil then
        callback({ code = vim.lsp.protocol.ErrorCodes.InternalError, message = err })
        return
      end

      if not word then
        callback(nil, { isIncomplete = false, items = {} })
        return
      end

      local range = {
        start = { line = lnum, character = char - #word },
        ["end"] = { line = lnum, character = char },
      }

      local backend
      backend, err = ensure_backend(bufnr)
      if err ~= nil then
        callback({ code = vim.lsp.protocol.ErrorCodes.InternalError, message = err })
        return
      end

      if not backend then
        callback(nil, { isIncomplete = false, items = {} })
        return
      end

      local items = vim
        .iter(backend:match(word))
        :map(function(entry)
          local label = string.format("%s [%s]", display_key(entry), entry.type)

          if entry.fields.author then label = label .. " " .. entry.fields.author end

          if entry.fields.year then label = label .. " (" .. entry.fields.year .. ")" end

          if #label > c.COMPLETION_MAX_LABEL then label = label:sub(1, c.COMPLETION_MAX_LABEL - 3) .. "..." end

          return {
            label = label,
            kind = vim.lsp.protocol.CompletionItemKind.Reference,
            textEdit = { newText = entry.key, range = range },
            data = { bufnr = bufnr },
          }
        end)
        :totable()

      callback(nil, { isIncomplete = false, items = items })
    end)
    if not ok then callback({ code = vim.lsp.protocol.ErrorCodes.InternalError, message = tostring(handler_err) }) end
  end)
end

--- Add details to a citation completion.
---@param params BibLspCompletionItem Completion item to resolve.
---@param callback BibLspCallback Receives the resolved item.
---@private
handlers["completionItem/resolve"] = function(params, callback)
  local bufnr = params.data and params.data.bufnr or vim.api.nvim_get_current_buf()
  local backend, err = ensure_backend(bufnr)
  if err ~= nil then return callback({ code = vim.lsp.protocol.ErrorCodes.InternalError, message = err }) end

  if not backend or not params.textEdit then
    callback(nil, params)
    return
  end

  local key = params.textEdit.newText
  local entry = backend:get(key)

  if not entry then
    callback(nil, params)
    return
  end

  params.detail = entry.type

  local content = backend:hover(key)

  if content then params.documentation = { kind = "markdown", value = content } end

  callback(nil, params)
end

--- Find the definition of a citation.
---@param params BibLspParams Document position of the citation.
---@param callback BibLspCallback Receives the definition location, or nil if absent.
---@private
handlers["textDocument/definition"] = function(params, callback)
  local backend, err = ensure_backend(vim.uri_to_bufnr(params.textDocument.uri))
  if err ~= nil then return callback({ code = vim.lsp.protocol.ErrorCodes.InternalError, message = err }) end

  if not backend then
    callback(nil, nil)
    return
  end

  local found
  found, err = citekey(params)
  if err ~= nil then return callback({ code = vim.lsp.protocol.ErrorCodes.InternalError, message = err }) end

  if not found then
    callback(nil, nil)
    return
  end

  local loc = backend:definition(found)

  callback(nil, loc)
end

--- Show details for a citation.
---@param params BibLspParams Document position of the citation.
---@param callback BibLspCallback Receives hover content, or nil if absent.
---@private
handlers["textDocument/hover"] = function(params, callback)
  local backend, err = ensure_backend(vim.uri_to_bufnr(params.textDocument.uri))
  if err ~= nil then return callback({ code = vim.lsp.protocol.ErrorCodes.InternalError, message = err }) end

  if not backend then
    callback(nil, nil)
    return
  end

  local found
  found, err = citekey(params)
  if err ~= nil then return callback({ code = vim.lsp.protocol.ErrorCodes.InternalError, message = err }) end

  if not found then
    callback(nil, nil)
    return
  end

  local content = backend:hover(found)

  if not content then
    callback(nil, nil)
    return
  end

  callback(nil, { contents = { kind = "markdown", value = content } })
end

--- Build code actions for a citation.
---@param params lsp.CodeActionParams Document range for the citation.
---@param callback BibLspCallback Receives code actions or an LSP error.
---@private
handlers["textDocument/codeAction"] = function(params, callback)
  local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
  local backend, err = ensure_backend(bufnr)
  if err ~= nil then return callback({ code = vim.lsp.protocol.ErrorCodes.InternalError, message = err }) end

  if not backend then
    callback(nil, nil)
    return
  end

  local key
  key, err = citekey_at(bufnr, params.range.start.line, params.range.start.character)
  if err ~= nil then return callback({ code = vim.lsp.protocol.ErrorCodes.InternalError, message = err }) end
  local entry = key and backend:get(key)

  if not entry then
    callback(nil, nil)
    return
  end

  require("bib.utils.actions").for_entry(entry, params, function(actions, action_err) callback(action_err, actions) end)
end

--- Execute a supported bibliography command.
---@param params lsp.ExecuteCommandParams Command and arguments to execute.
---@param callback BibLspCallback Receives the command response or an LSP error.
---@private
handlers["workspace/executeCommand"] = function(params, callback)
  if params.command == "bib.open_pdf" and params.arguments and params.arguments[1] ~= nil then
    local path = params.arguments[1]
    if type(path) ~= "string" then return callback({ code = vim.lsp.protocol.ErrorCodes.InvalidParams, message = "PDF path must be a string" }) end

    local err = require("bib.utils").open(path)
    if err ~= nil then return callback({ code = vim.lsp.protocol.ErrorCodes.InternalError, message = err }) end
  end
  callback(nil, nil)
end

handlers.notify = {}

--- Create the in-process bibliography server.
---@param dispatchers vim.lsp.rpc.Dispatchers Callbacks used to report server events.
---@return BibLspServer server In-process LSP server.
function lsp.server(dispatchers)
  state.stopped = false
  return {
    request = function(method, params, callback)
      local handler = handlers[method]

      if not handler then
        callback(nil, nil)
        return true
      end

      local responded = false
      --- Send at most one response to a request.
      ---@param err lsp.ResponseError|nil LSP error, or nil on success.
      ---@param result? any Response value, or nil.
      ---@private
      local function respond(err, result)
        if responded then return end

        responded = true
        callback(err, result)
      end
      local ok, err = pcall(handler, params, respond)
      if not ok then
        if responded then
          vim.lsp.log.error("[bib.lsp] handler error (" .. method .. "): " .. tostring(err))
          return true
        end

        respond({ code = vim.lsp.protocol.ErrorCodes.InternalError, message = tostring(err) })
      end

      return true
    end,
    notify = function(method, _)
      if method == "exit" then
        state.stopped = true
        dispatchers.on_exit(0, 15)
        return
      end

      local handler = handlers.notify[method]
      if not handler then return end

      local ok, err = pcall(handler)
      if not ok then vim.lsp.log.error("[bib.lsp] notification error (" .. method .. "): " .. tostring(err)) end
    end,
    is_closing = function() return state.stopped end,
    terminate = function() state.stopped = true end,
  }
end

--- Return the backend for a buffer.
---@param bufnr integer|nil Buffer handle, or nil for the current buffer.
---@return Backend|nil backend Buffer backend, or nil if unset.
function lsp.backend(bufnr) return backend_for(bufnr or vim.api.nvim_get_current_buf()) end

--- Select backend for a buffer: bib first, zotero fallback
---@param bufnr integer Buffer whose backend is selected.
---@return Backend|nil backend Selected backend, or nil if none loads.
---@return string|nil error Backend load error, or nil on success.
function lsp.pick(bufnr)
  local bib = require("bib.backends.bib")
  local backend, bib_err = bib.load(bufnr)
  if bib_err ~= nil then vim.lsp.log.warn("[bib.lsp] bib backend failed: " .. tostring(bib_err)) end

  if backend and #backend:all() > 0 then
    set_backend(bufnr, backend)
    return backend
  end

  local zotero = require("bib.backends.zotero")
  local err = zotero:load()

  if err == nil then
    set_backend(bufnr, zotero)
  else
    state.backends[bufnr] = nil
    vim.lsp.log.warn("[bib.lsp] zotero backend failed: " .. tostring(err))
    return nil, bib_err or err
  end

  return backend_for(bufnr)
end

--- Register bibliography reload and attachment hooks.
function lsp.attach()
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("BibReloadBibliography", { clear = true }),
    callback = function(args)
      local name = vim.api.nvim_buf_get_name(args.buf)
      if name == "" then return end

      local written = vim.uv.fs_realpath(name) or vim.fs.normalize(name)
      local failure
      vim.iter(pairs(state.backends)):each(function(bufnr, backend)
        if not backend.path or not vim.api.nvim_buf_is_valid(bufnr) then return end
        local path = vim.uv.fs_realpath(backend.path) or vim.fs.normalize(backend.path)
        if path ~= written then return end
        local err = backend:load(bufnr)
        if err ~= nil then
          vim.lsp.log.warn("[bib.lsp] bibliography reload failed: " .. tostring(err))
          failure = failure or err
        end
      end)
      if failure ~= nil then vim.notify("[bib] bibliography reload failed: " .. tostring(failure), vim.log.levels.ERROR) end
    end,
  })
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

        vim.lsp.buf_detach_client(bufnr, client.id)
        if vim.tbl_isempty(client.attached_buffers) then client:stop() end
        return
      end

      vim.api.nvim_create_autocmd("BufWritePost", {
        buffer = bufnr,
        group = vim.api.nvim_create_augroup("BibReloadBackend" .. bufnr, { clear = true }),
        callback = function()
          local backend = backend_for(bufnr)
          if not backend then return end
          local err = backend:load(bufnr)
          if err ~= nil then vim.notify("[bib] backend reload failed: " .. tostring(err), vim.log.levels.ERROR) end
        end,
      })

      vim.api.nvim_create_autocmd("BufDelete", {
        buffer = bufnr,
        group = vim.api.nvim_create_augroup("BibForgetBackend" .. bufnr, { clear = true }),
        callback = function() state.backends[bufnr] = nil end,
      })
    end,
  })
end

return lsp
