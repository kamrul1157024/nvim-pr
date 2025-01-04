local Popup = require("nui.popup")
local event = require("nui.utils.autocmd").event
local Job = require("plenary.job")

---@alias pr_description { url: string, title: string}
---@alias command { program: string, args: string[]}
---@class popup
---@field bufnr number
---@field unmount function

---@return number
local function get_cursor_line_number()
	local r, _ = unpack(vim.api.nvim_win_get_cursor(0))
	return r
end

---@param line string
local function notify(line)
	vim.print(line)
end

---@param command command
---@return string|nil
local function exec_bash_command(command, callback)
	Job:new({
		command = command.program,
		args = command.args,
		cwd = vim.fn.getcwd(),
		env = vim.fn.environ(),
		on_exit = vim.schedule_wrap(function(response, exit_code)
			if exit_code == 0 then
				callback(nil, table.concat(response:result(), "\n"))
				return
			end
			callback(vim.inspect(command), nil)
		end),
	}):start()
end

local function get_remote_repos(callback)
	exec_bash_command({ program = "git", args = { "remote", "-v" }, env = {} }, function(err, remote_list_str)
		if err ~= nil then
			notify("Error while getting remote list" .. err)
			callback(err, nil)
			return
		end
		if remote_list_str == nil then
			notify("remote list str is nil")
			callback(err, nil)
			return
		end

		local is_remote_repo_exist = {}

		for remote_name in string.gmatch(remote_list_str, "[^\n]+") do
			local c = 0
			local remote_url = ""

			for s in string.gmatch(remote_name, "[^%s]+") do
				c = c + 1
				if c == 2 then
					remote_url = s
				end
			end

			local remote_repo_dot_git = ""
			for s in string.gmatch(remote_url, "[^:]+") do
				remote_repo_dot_git = s
			end

			local remote_repo = ""
			for s in string.gmatch(remote_repo_dot_git, "[^.]+") do
				remote_repo = s
				break
			end

			is_remote_repo_exist[remote_repo] = true
		end

		local remote_repo_list = {}
		for k, _ in pairs(is_remote_repo_exist) do
			table.insert(remote_repo_list, k)
		end

		return callback(nil, remote_repo_list)
	end)
end

---@return string
local function get_current_file_path()
	return vim.fn.expand("%:p")
end

---@param line_no number
---@param file_path string
---@param callback function
local function get_git_blame_commit_hash(line_no, file_path, callback)
	exec_bash_command({
		program = "git",
		args = { "blame", "-l", "-L", string.format("%d,%d", line_no, line_no), file_path },
		env = {},
	}, function(err, command_output)
		if err ~= nil then
			notify("Error while getting git blame output" .. err)
			callback(err, nil)
			return
		end
		if command_output == nil then
			notify("Unable to get git blame output")
			callback("Unable to get git blame output", nil)
			return
		end

		for s in string.gmatch(command_output, "%w+") do
			return callback(nil, s)
		end
	end)
end

---@param title string
---@return popup
local function show_popup(title)
	local popup = Popup({
		position = "50%",
		size = {
			width = 100,
			height = 40,
		},
		enter = true,
		focusable = true,
		zindex = 50,
		relative = "editor",
		border = {
			padding = {
				top = 2,
				bottom = 2,
				left = 3,
				right = 3,
			},
			style = "rounded",
			text = {
				top = title,
				top_align = "center",
			},
		},
		buf_options = {
			modifiable = true,
			readonly = false,
		},
		win_options = {
			winblend = 10,
			winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
		},
	})

	-- mount/open the component
	popup:mount()

	-- unmount component when cursor leaves buffer
	popup:on(event.BufLeave, function()
		popup:unmount()
	end)
	return popup
end

---@param popup popup
local function attach_popup_close_keymap(popup)
	vim.api.nvim_buf_set_keymap(popup.bufnr, "n", "q", "", {
		desc = "Close the popup window",
		callback = function()
			popup:unmount()
		end,
	})
end

---@param pr_description pr_description|nil
---@param callback function
local function open_pr_description_in_browser(pr_description, callback)
	if pr_description == nil or pr_description["url"] == nil then
		notify("No PR Description found")
		callback("No PR Description found", nil)
		return
	end
	exec_bash_command({ program = "gh", args = { "pr", "view", pr_description["url"], "-w" } }, function(err, data)
		if err ~= nil then
			callback(err, nil)
			return
		end
		return callback(nil, data)
	end)
end

---@param popup popup
---@param pr_description pr_description
---@param callback function
local function attach_pr_open_keymap(popup, pr_description, callback)
	vim.api.nvim_buf_set_keymap(popup.bufnr, "n", "<CR>", "", {
		desc = "Open the Pull Request on the browser",
		callback = function()
			open_pr_description_in_browser(pr_description, callback)
		end,
	})
end

---@param popup popup
local function highlight_buffer_using_markdown_highlighter(popup)
	vim.api.nvim_set_option_value("filetype", "markdown", { buf = popup.bufnr })
end

---@param pr_url string
---@param callback function
local function get_pr_details_text(pr_url, callback)
	exec_bash_command({ program = "gh", args = { "pr", "view", pr_url } }, function(err, pr_details_text)
		if err ~= nil then
			notify("Error while getting PR Details")
			callback(err, nil)
			return
		end
		return callback(nil, pr_details_text)
	end)
end

---@param popup popup
---@param lines string[]
local function write_text_to_popup(popup, lines)
	vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
end

---@param popup popup
---@param pr_details_text string
local function write_on_popup(popup, pr_details_text)
	local lines = {}
	for line in string.gmatch(pr_details_text, "[^\r\n]+") do
		table.insert(lines, line)
	end
	write_text_to_popup(popup, lines)
end

---@param commit_hash string|nil
---@param callback function
local function get_pr_description(commit_hash, callback)
	if commit_hash == nil then
		return nil
	end

	get_remote_repos(function(err, remote_repos)
		if err ~= nil then
			callback(err, nil)
			return
		end
		local pr_search_args = {
			"search",
			"prs",
			string.format("hash:%s", commit_hash),
		}

		for _, remote_repo in ipairs(remote_repos) do
			table.insert(pr_search_args, "-R")
			table.insert(pr_search_args, remote_repo)
		end

		table.insert(pr_search_args, "--json")
		table.insert(pr_search_args, "url,title")

		exec_bash_command({
			program = "gh",
			args = pr_search_args,
		}, function(pr_err, prs_description_output)
			if pr_err ~= nil then
				notify("Error while getting PR Description" .. pr_err)
				callback(pr_err, nil)
				return
			end
			if prs_description_output == nil then
				notify("PR Description output is Null")
				callback("PR Description output is Null", nil)
				return
			end
			if pcall(vim.json.decode, prs_description_output) then
				local pr_descriptions = vim.json.decode(prs_description_output)
				if pr_descriptions[1] == nil then
					notify("No PR Description found")
					callback("No PR Description found", nil)
					return
				end
				return callback(nil, pr_descriptions[1])
			end
			notify("Error while decoding PR Description")
			callback("Error while decoding PR Description", nil)
		end)
	end)
end

---@param callback function
local function get_cursor_commit_hash(callback)
	local line_no = get_cursor_line_number()
	get_git_blame_commit_hash(line_no, get_current_file_path(), function(err, commit_hash)
		callback(nil, commit_hash)
	end)
end

---@param commit_hash string|nil
local function load_pr_information(commit_hash)
	local loading_popup = show_popup("Loading PR Description...")
	attach_popup_close_keymap(loading_popup)
	get_pr_description(commit_hash, function(err, pr_description)
		if err ~= nil then
			write_on_popup(loading_popup, "Unable to get PR Description")
			return
		end
		get_pr_details_text(pr_description["url"], function(err, pr_details_text)
			if err ~= nil or pr_details_text == nil then
				write_on_popup(loading_popup, "Unable to get PR Details")
				return
			end

			loading_popup:unmount()

			local popup = show_popup(pr_description["title"])
			highlight_buffer_using_markdown_highlighter(popup)
			attach_popup_close_keymap(popup)
			attach_pr_open_keymap(popup, pr_description, function()
				notify("Opening PR Description in Browser")
			end)
			write_on_popup(popup, pr_details_text)
		end)
	end)
end

---@param command string
local function exec_command(command)
	get_cursor_commit_hash(function(err, commit_hash)
		if err ~= nil then
			notify("Error while getting commit hash")
			return
		end

		if command == "open" then
			load_pr_information(commit_hash)
		elseif command == "open_in_browser" then
			notify("Opening PR Description in Browser")
			get_pr_description(commit_hash, function(d_err, pr_description)
				if err ~= nil or pr_description == nil then
					notify("No PR Description found" .. d_err)
					return
				end
				open_pr_description_in_browser(pr_description, function(b_err)
					if err ~= nil then
						notify("Error while opening PR Description in Browser" .. b_err)
						return
					end
					notify("Opened PR Description in Browser")
				end)
			end)
		end
	end)
end

local function setup()
	vim.api.nvim_create_user_command("PR", function(opts)
		exec_command(opts.args)
	end, {
		nargs = "?",
		desc = "Pull Request Information",
		complete = function()
			return { "open", "open_in_browser" }
		end,
	})
end

return {
	setup = setup,
}
