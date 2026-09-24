local M = {}

function M.setup(options)
	options = options or {}
	local prepare_focus = options.prepare_focus or function(window, callback)
		callback(true, window)
	end

	hl.unbind("ALT + TAB")
	hl.unbind("ALT + SHIFT + TAB")

	local LEFT_ALT = 64
	local RIGHT_ALT = 108
	local order = {}
	local session
	local alt_origin_address
	local preparation_active = false
	local queued_focus
	local finalizing = false
	local alt_keys_down = {}
	local state_path = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/omarchy-window-switcher.json"

	local function remove_address(list, address)
		for index, candidate in ipairs(list or {}) do
			if candidate == address then
				table.remove(list, index)
				return index
			end
		end
	end

	local function promote(address)
		remove_address(order, address)
		table.insert(order, 1, address)
	end

	local function get_window(address)
		local window = address and hl.get_window("address:" .. address) or nil
		if window and window.mapped then
			return window
		end
	end

	local function workspace_selector(workspace)
		if workspace.name:match("^%d+$") or workspace.name:match("^special:") then
			return workspace.name
		end

		return "name:" .. workspace.name
	end

	local function workspace_is_active(workspace)
		local active = hl.get_active_workspace()
		if active and active.id == workspace.id then
			return true
		end

		local active_special = hl.get_active_special_workspace()
		return active_special and active_special.id == workspace.id
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

	local function write_state(content)
		pcall(function()
			local file = io.open(state_path, "w")
			if file then
				file:write(content, "\n")
				file:close()
			end
		end)
	end

	local function close_overlay()
		write_state('{"version":1,"open":false}')
	end

	local function publish_overlay()
		if not session then
			close_overlay()
			return
		end

		local rows = {}
		local selected_index = 0
		for index, address in ipairs(session.history) do
			local window = get_window(address)
			if window then
				table.insert(
					rows,
					'{"title":' .. json_string(window.title) .. ',"className":' .. json_string(window.class) .. "}"
				)
				if index == session.index then
					selected_index = #rows - 1
				end
			end
		end

		if #rows == 0 then
			close_overlay()
			return
		end

		write_state(
			'{"version":1,"open":true,"monitor":'
				.. json_string(session.monitor)
				.. ',"selected":'
				.. selected_index
				.. ',"windows":['
				.. table.concat(rows, ",")
				.. "]}"
		)
	end

	local function safely_publish_overlay()
		pcall(publish_overlay)
	end

	local function sync_order()
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
		for _, address in ipairs(order) do
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
		order = synced
	end

	local run_focus_request

	local function finish_focus_request(request, success)
		preparation_active = false
		if request.completed then
			request.completed(success)
		end

		local next_request = queued_focus
		queued_focus = nil
		if next_request then
			run_focus_request(next_request)
		end
	end

	local function wait_for_focus(request)
		local attempts = 0
		local timer
		timer = hl.timer(function()
			attempts = attempts + 1
			local active = hl.get_active_window()
			if active and active.address == request.address then
				timer:set_enabled(false)
				finish_focus_request(request, true)
			elseif attempts >= 20 or not get_window(request.address) then
				timer:set_enabled(false)
				finish_focus_request(request, false)
			end
		end, { timeout = 50, type = "repeat" })
	end

	run_focus_request = function(request)
		preparation_active = true
		local selected = get_window(request.address)
		if not selected then
			finish_focus_request(request, false)
			return
		end

		prepare_focus(selected, function(ready)
			if not ready then
				finish_focus_request(request, false)
				return
			end

			local current = get_window(request.address)
			if not current or not current.workspace then
				finish_focus_request(request, false)
				return
			end

			if not workspace_is_active(current.workspace) then
				hl.dispatch(hl.dsp.focus({ workspace = workspace_selector(current.workspace) }))
			end
			hl.dispatch(hl.dsp.focus({ window = current }))
			hl.dispatch(hl.dsp.window.bring_to_top())
			wait_for_focus(request)
		end)
	end

	local function request_focus(window, completed)
		local request = { address = window.address, completed = completed }
		if preparation_active then
			queued_focus = request
		else
			run_focus_request(request)
		end
	end

	local function focus_selection(current_session, completed)

		while #current_session.history > 0 do
			local selected = get_window(current_session.history[current_session.index])
			if selected then
				request_focus(selected, completed)
				return selected
			end

			table.remove(current_session.history, current_session.index)
			if #current_session.history == 0 then
				return
			elseif current_session.direction == 1 then
				current_session.index = ((current_session.index - 1) % #current_session.history) + 1
			else
				current_session.index = ((current_session.index - 2) % #current_session.history) + 1
			end
		end
	end

	local function begin_session(direction)
		sync_order()
		local active = get_window(alt_origin_address) or hl.get_active_window()
		if active then
			promote(active.address)
			if #order < 2 then
				return nil
			end

			local history = { active.address }
			for _, address in ipairs(order) do
				if address ~= active.address then
					table.insert(history, address)
				end
			end
			local monitor = active.monitor or hl.get_active_monitor()
			return {
				history = history,
				index = direction == 1 and 2 or #history,
				direction = direction,
				monitor = monitor and monitor.name or "",
				origin = active.address,
			}
		end

		if #order == 0 then
			return nil
		end

		local monitor = hl.get_active_monitor()
		return {
			history = { table.unpack(order) },
			index = direction == 1 and 1 or #order,
			direction = direction,
			monitor = monitor and monitor.name or "",
			origin = nil,
		}
	end

	local function switch_by_history(direction)
		if finalizing then
			return
		end

		if not session then
			session = begin_session(direction)
			if not session then
				return
			end
		else
			session.index = ((session.index - 1 + direction) % #session.history) + 1
			session.direction = direction
		end

		focus_selection(session)
		safely_publish_overlay()
	end

	local function end_session()
		if not session then
			return
		end

		local completed = session
		finalizing = true
		local selected_address
		local selected = focus_selection(completed, function(success)
			if success and selected_address then
				promote(selected_address)
			end
			finalizing = false
		end)
		selected_address = selected and selected.address or nil
		if not selected then
			finalizing = false
		end
		session = nil
		close_overlay()
	end

	close_overlay()

	o.bind("ALT + TAB", "Cycle windows by recent use", function()
		switch_by_history(1)
	end)
	o.bind("ALT + SHIFT + TAB", "Cycle windows by recent use in reverse", function()
		switch_by_history(-1)
	end)

	hl.on("window.active", function(window)
		if not session and not preparation_active and not finalizing and window then
			promote(window.address)
		end
	end)

	hl.on("window.close", function(window)
		local address = window.address
		remove_address(order, address)
		if not session then
			return
		end

		local removed_index = remove_address(session.history, address)
		if not removed_index then
			return
		elseif #session.history == 0 then
			session = nil
			close_overlay()
		elseif removed_index < session.index then
			session.index = session.index - 1
			safely_publish_overlay()
		elseif removed_index == session.index then
			if session.direction == 1 then
				session.index = ((session.index - 1) % #session.history) + 1
			else
				session.index = ((session.index - 2) % #session.history) + 1
			end
			local current_session = session
			hl.timer(function()
				if session == current_session then
					focus_selection(current_session)
					safely_publish_overlay()
				end
			end, { timeout = 1, type = "oneshot" })
		else
			safely_publish_overlay()
		end
	end)

	-- Raw releases reliably end a session even when ALT+TAB consumes the keypress.
	hl.on("input.keyboard.key", function(keycode, _, key_state)
		if keycode ~= LEFT_ALT and keycode ~= RIGHT_ALT then
			return
		end

		if key_state ~= 0 and not alt_keys_down[LEFT_ALT] and not alt_keys_down[RIGHT_ALT] then
			local active = hl.get_active_window()
			alt_origin_address = active and active.address or nil
		end
		alt_keys_down[keycode] = key_state ~= 0
		if key_state == 0 and not alt_keys_down[LEFT_ALT] and not alt_keys_down[RIGHT_ALT] then
			end_session()
			alt_origin_address = nil
		end
	end)
end

return M
