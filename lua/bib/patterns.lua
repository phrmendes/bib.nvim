---@class BibPatterns
---@field concat_sep string Concatenation separator in @string values (#)
---@field whitespace string Collapse whitespace (abstract normalization)
---@field key_left string Extract citation key chars before cursor (anchored at last @)
---@field key_right string Extract citation key chars at and after cursor
---@field inline_partial string Extract partial citation key from inline node (completion prefix)
---@field tex_root string Extract path from LaTeX !TeX root magic comment
---@field citekey_rest string Extract citekey chars after ITEMID#
---@field zotkey_strip string Strip #citekey suffix from zotero composite key
---@field year string Extract YYYY year from date field
---@field lastname string Extract last word from an author name
---@field bib_search string Match :Bib search command
---@field conceal_scan string Match @citekey or @ITEMID#citekey for conceal marks
---@field storage_prefix string Detect storage: prefix in Zotero attachment paths
return {
	concat_sep = "%s*#%s*",
	whitespace = "%s+",
	key_left = ".*@([%w%-#]*)$",
	key_right = "^([%w%-#]*)",
	inline_partial = ".*@(%S*)$",
	tex_root = "%%+%s*!%s*[Tt][Ee][Xx]%s+root%s*=%s*(.-)%s*$",
	citekey_rest = "[%w%-]+",
	zotkey_strip = "#.*",
	year = "^(%d%d%d%d)",
	lastname = "(%S+)$",
	bib_search = "Bib%s+search",
	conceal_scan = "()@([%w%-#]+)",
	storage_prefix = "^storage:",
}
