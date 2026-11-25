local patterns = require("bib.patterns")

---@type table
local actions = {}

--- Build code actions for a Zotero entry
---@param entry BibEntry|ZoteroEntry
---@param params table LSP code action params
---@return table[]
function actions.build(entry, params)
	if not entry.zotkey then return {} end
	local db_path = require("bib.backends.zotero").database_path()
	if not db_path then return {} end

	local db
	local ok_open, err = pcall(function()
		db = require("sqlite").new(db_path)
		db:open({ busy_timeout = 500 })
	end)

	if not ok_open or not db then
		if db then pcall(db.close, db) end
		vim.notify("[bib] could not open the Zotero database: " .. tostring(err), vim.log.levels.ERROR)
		return {}
	end

	local ok, result = pcall(function() return actions._build(db, entry, params) end)
	pcall(db.close, db)

	if not ok then
		vim.notify("[bib] code action failed: " .. tostring(result), vim.log.levels.ERROR)
		return {}
	end

	return result
end

--- Read attachments and notes through an open database handle.
---@param db table
---@param entry BibEntry|ZoteroEntry
---@param params table LSP code action params
---@return table[]
function actions._build(db, entry, params)
	local backends = require("bib.utils.backends")
	local result = {}

	local pdfs = db:eval(backends.read_sql("attachments"), { key = entry.zotkey })

	if type(pdfs) == "table" and #pdfs > 0 then
		local pdf_path = pdfs[1].path

		if pdf_path:find(patterns.storage_prefix) then pdf_path = vim.fs.joinpath(vim.fs.dirname(backends.find_zotero_db()), "storage", pdfs[1].attachKey, pdf_path:sub(9)) end

		result[#result + 1] = {
			title = "Open PDF",
			kind = "quickfix",
			command = {
				title = "Open",
				command = "bib.open_pdf",
				arguments = { pdf_path },
			},
		}
	end

	local notes = db:eval(backends.read_sql("notes"), { key = entry.zotkey })

	if type(notes) == "table" and #notes > 0 then
		local to_markdown = require("bib.utils.notes").to_markdown
		local lines = vim.iter(notes):fold({}, function(acc, n)
			local body = to_markdown(n.note) or n.note
			vim.list_extend(acc, vim.split(body, "\n"))
			acc[#acc + 1] = ""
			return acc
		end)

		if #lines > 0 then lines[#lines] = nil end

		result[#result + 1] = {
			title = "Get notes from Zotero",
			kind = "refactor",
			edit = {
				changes = {
					[params.textDocument.uri] = {
						{
							range = {
								start = { line = params.range["end"].line + 1, character = 0 },
								["end"] = { line = params.range["end"].line + 1, character = 0 },
							},
							newText = table.concat(lines, "\n") .. "\n",
						},
					},
				},
			},
		}
	end

	return result
end

return actions
