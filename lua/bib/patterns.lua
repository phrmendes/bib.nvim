---@class BibPatterns
---@field concat_sep string Concatenation separator in @string values (#)
---@field whitespace string Collapse whitespace (abstract normalization)
---@field key_left string Extract citation key chars before cursor (anchored at last @)
---@field key_right string Extract citation key chars at and after cursor
---@field inline_partial string Extract partial citation key from inline node (completion prefix)
---@field tex_root string Extract path from LaTeX !TeX root magic comment
return {
	concat_sep = "%s*#%s*",
	whitespace = "%s+",
	key_left = ".*@([%w%-]*)$",
	key_right = "^([%w%-]*)",
	inline_partial = ".*@(%S*)$",
	tex_root = "%%+%s*!%s*[Tt][Ee][Xx]%s+root%s*=%s*(.-)%s*$",
}
