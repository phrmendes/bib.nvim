local patterns = require("bib.patterns")

---@type table
local actions = {}

--- Build code actions for a Zotero entry
---@param entry BibEntry|ZoteroEntry
---@param params table LSP code action params
---@return table[]
function actions.build(entry, params)
	if not entry.zotkey then return {} end
	local backends = require("bib.utils.backends")
	local db_path = backends.find_zotero_db()
	if not db_path then return {} end

	local db = require("sqlite").new(db_path)
	db:open()

	local result = {}

	local pdfs = db:eval(backends.read_sql("attachments"), { key = entry.zotkey })

	if pdfs and #pdfs > 0 then
		local pdf_path = pdfs[1].path

		if pdf_path:find(patterns.storage_prefix) then pdf_path = vim.fs.joinpath(vim.fs.dirname(db_path), "storage", pdfs[1].attachKey, pdf_path:sub(9)) end

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

	if notes and #notes > 0 then
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

	db:close()
	return result
end

return actions
