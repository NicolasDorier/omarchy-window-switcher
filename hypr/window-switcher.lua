hl.unbind("ALT + TAB")
hl.unbind("ALT + SHIFT + TAB")

local alt_tab_order
local alt_tab_history
local alt_tab_index
local alt_tab_direction
local alt_tab_monitor
local alt_tab_origin_address
local alt_keys_down = {}
local alt_tab_state_path = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/omarchy-window-switcher.json"

local function remove_address(list, address)
	for index, candidate in ipairs(list or {}) do
		if candidate == address then
			table.remove(list, index)
			return index
		end
	end
end

local function promote(address)
	alt_tab_order = alt_tab_order or {}
	remove_address(alt_tab_order, address)
	table.insert(alt_tab_order, 1, address)
end

local function get_window(address)
	local window = hl.get_window("address:" .. address)
	if window and window.mapped then
		return window
	end
end

local function json_string(value)
	local escapes = {
		['"'] = '\\"',
		["\\"] = "\\\\",
		["\b"] = "\\b",
		["\f"] = "\\f",
		["\n"] = "\\n",
		["\r"] = "\\r",
		["\t"] = "\\t",
	}
	return '"'
		.. tostring(value or ""):gsub('[%z\1-\31\\"]', function(character)
			return escapes[character] or string.format("\\u%04x", string.byte(character))
		end)
		.. '"'
end

local function write_alt_tab_state(content)
	pcall(function()
		local file = io.open(alt_tab_state_path, "w")
		if file then
			file:write(content, "\n")
			file:close()
		end
	end)
end

local function close_alt_tab_overlay()
	write_alt_tab_state('{"version":1,"open":false}')
end

local function publish_alt_tab_overlay()
	if not alt_tab_history or not alt_tab_index then
		close_alt_tab_overlay()
		return
	end

	local rows = {}
	local selected_index = 0
	for index, address in ipairs(alt_tab_history) do
		local window = get_window(address)
		if window then
			local workspace = window.workspace
			table.insert(
				rows,
				'{"title":'
					.. json_string(window.title)
					.. ',"className":'
					.. json_string(window.class)
					.. ',"workspace":'
					.. json_string(workspace and workspace.name or "?")
					.. "}"
			)
			if index == alt_tab_index then
				selected_index = #rows - 1
			end
		end
	end

	if #rows == 0 then
		close_alt_tab_overlay()
		return
	end

	write_alt_tab_state(
		'{"version":1,"open":true,"monitor":'
			.. json_string(alt_tab_monitor)
			.. ',"selected":'
			.. selected_index
			.. ',"windows":['
			.. table.concat(rows, ",")
			.. "]}"
	)
end

local function safely_publish_alt_tab_overlay()
	pcall(publish_alt_tab_overlay)
end

close_alt_tab_overlay()

local function sync_alt_tab_order()
	local windows = hl.get_windows({ mapped = true })
	table.sort(windows, function(left, right)
		return left.focus_history_id < right.focus_history_id
	end)

	local eligible = {}
	for _, window in ipairs(windows) do
		if window.focus_history_id >= 0 then
			eligible[window.address] = true
		end
	end

	local synced = {}
	for _, address in ipairs(alt_tab_order or {}) do
		if eligible[address] then
			table.insert(synced, address)
			eligible[address] = nil
		end
	end
	for _, window in ipairs(windows) do
		if eligible[window.address] then
			table.insert(synced, window.address)
		end
	end
	alt_tab_order = synced
end

local function focus_alt_tab_selection()
	while alt_tab_history and #alt_tab_history > 0 do
		local selected = get_window(alt_tab_history[alt_tab_index])
		if selected then
			hl.dispatch(hl.dsp.focus({ window = "address:" .. selected.address }))
			hl.dispatch(hl.dsp.window.bring_to_top())
			return selected
		end

		table.remove(alt_tab_history, alt_tab_index)
		if #alt_tab_history == 0 then
			return
		elseif alt_tab_direction == 1 then
			alt_tab_index = ((alt_tab_index - 1) % #alt_tab_history) + 1
		else
			alt_tab_index = ((alt_tab_index - 2) % #alt_tab_history) + 1
		end
	end
end

local function end_alt_tab()
	if not alt_tab_history then
		return
	end

	local selected = focus_alt_tab_selection()
	if selected then
		promote(selected.address)
	end
	close_alt_tab_overlay()

	alt_tab_history = nil
	alt_tab_index = nil
	alt_tab_direction = nil
	alt_tab_monitor = nil
	alt_tab_origin_address = nil
end

local function switch_by_history(direction)
	if not alt_tab_history then
		sync_alt_tab_order()
		local active = alt_tab_origin_address and get_window(alt_tab_origin_address) or hl.get_active_window()
		if not active then
			if #alt_tab_order == 0 then
				return
			end

			alt_tab_history = { table.unpack(alt_tab_order) }
			alt_tab_index = direction == 1 and 1 or #alt_tab_history
			local monitor = hl.get_active_monitor()
			alt_tab_monitor = monitor and monitor.name or ""
		else
			promote(active.address)

			if #alt_tab_order < 2 then
				return
			end

			alt_tab_history = { active.address }
			for _, address in ipairs(alt_tab_order) do
				if address ~= active.address then
					table.insert(alt_tab_history, address)
				end
			end
			alt_tab_index = direction == 1 and 2 or #alt_tab_history
			local monitor = active.monitor or hl.get_active_monitor()
			alt_tab_monitor = monitor and monitor.name or ""
		end
	else
		alt_tab_index = ((alt_tab_index - 1 + direction) % #alt_tab_history) + 1
	end

	alt_tab_direction = direction
	focus_alt_tab_selection()
	safely_publish_alt_tab_overlay()
end

o.bind("ALT + TAB", "Cycle windows by recent use", function()
	switch_by_history(1)
end)
o.bind("ALT + SHIFT + TAB", "Cycle windows by recent use in reverse", function()
	switch_by_history(-1)
end)

hl.on("window.active", function(window)
	if not alt_tab_history and window then
		promote(window.address)
	end
end)

hl.on("window.close", function(window)
	local address = window.address
	remove_address(alt_tab_order, address)

	if not alt_tab_history then
		return
	end

	local removed_index = remove_address(alt_tab_history, address)
	if not removed_index then
		return
	end

	if #alt_tab_history == 0 then
		close_alt_tab_overlay()
		alt_tab_history = nil
		alt_tab_index = nil
		alt_tab_direction = nil
		alt_tab_monitor = nil
	elseif removed_index < alt_tab_index then
		alt_tab_index = alt_tab_index - 1
		safely_publish_alt_tab_overlay()
	elseif removed_index == alt_tab_index then
		if alt_tab_direction == 1 then
			alt_tab_index = ((alt_tab_index - 1) % #alt_tab_history) + 1
		else
			alt_tab_index = ((alt_tab_index - 2) % #alt_tab_history) + 1
		end
		hl.timer(function()
			focus_alt_tab_selection()
			safely_publish_alt_tab_overlay()
		end, { timeout = 1, type = "oneshot" })
	else
		safely_publish_alt_tab_overlay()
	end
end)

-- Raw key releases reliably end the session even when ALT+TAB consumed the keypress.
hl.on("input.keyboard.key", function(keycode, _, state)
	if keycode == 64 or keycode == 108 then
		if state ~= 0 and not alt_keys_down[64] and not alt_keys_down[108] then
			local active = hl.get_active_window()
			alt_tab_origin_address = active and active.address or nil
		end
		alt_keys_down[keycode] = state ~= 0
		if state == 0 and not alt_keys_down[64] and not alt_keys_down[108] then
			end_alt_tab()
			alt_tab_origin_address = nil
		end
	end
end)
