---@generic T : table
---@param loaders table<string, fun(): T>
---@return table<string, T>
return function(loaders)
	return setmetatable({}, {
		__index = function(t, k)
			local loader = loaders[k]
			if not loader then return nil end
			local v = loader()
			rawset(t, k, v)
			return v
		end,
	})
end
