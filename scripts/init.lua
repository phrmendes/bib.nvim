vim.g.did_bib_plugin = true

vim.opt.runtimepath:append(vim.uv.cwd())
package.path = vim.fs.joinpath(vim.uv.cwd(), "lua", "?.lua") .. ";" .. vim.fs.joinpath(vim.uv.cwd(), "lua", "?", "init.lua") .. ";" .. package.path

if #vim.api.nvim_list_uis() == 0 then
	local packages_path = "deps"
	local mini_path = vim.fs.joinpath(packages_path, "pack", "deps", "start", "mini.nvim")

	if not vim.uv.fs_stat(mini_path) then
		local mini_repo = "https://github.com/echasnovski/mini.nvim"
		local out = vim.system({ "git", "clone", "--filter=blob:none", mini_repo, mini_path }):wait()
		if out.code ~= 0 then os.exit(1) end
	else
		local out = vim.system({ "git", "-C", mini_path, "pull" }):wait()
		if out.code ~= 0 then os.exit(1) end
	end

	local grammars_dir = vim.env.BIB_GRAMMARS

	if grammars_dir then vim.iter({ "bibtex", "latex", "markdown", "markdown_inline", "yaml" }):each(function(name)
		local so = vim.fs.joinpath(grammars_dir, name .. ".so")
		if not vim.uv.fs_stat(so) then return end
		pcall(vim.treesitter.language.add, name, { path = so })
	end) end

	local sqlite_path = vim.fs.joinpath(packages_path, "sqlite.lua")
	if not vim.uv.fs_stat(sqlite_path) then
		local out = vim.system({ "git", "clone", "--filter=blob:none", "https://github.com/kkharji/sqlite.lua", sqlite_path }):wait()
		if out.code ~= 0 then vim.notify("bib.nvim: failed to clone sqlite.lua", vim.log.levels.WARN) end
	end

	if not vim.iter(vim.opt.runtimepath:get()):find(function(p) return p == sqlite_path end) then vim.opt.runtimepath:append(sqlite_path) end
	local pkg_rtp = vim.fs.joinpath(vim.uv.cwd(), packages_path)
	if not vim.iter(vim.opt.runtimepath:get()):find(function(p) return p == pkg_rtp end) then vim.opt.runtimepath:append(pkg_rtp) end

	require("mini.test").setup()
	require("mini.doc").setup()
end
