local Popup = require("nui.popup")
local event = require("nui.utils.autocmd").event

---@alias pr_description { url: string, title: string}
---@class popup
---@field bufnr number
---@field unmount function

---@return number
local function get_cursor_line_number()
	local r, _ = unpack(vim.api.nvim_win_get_cursor(0))
	return r
end

---@param line string
local function log(line)
	vim.print(line)
end

---@param command string
---@return string|nil
local function exec_bash_command(command)
	local handle = io.popen(command)
	if handle == nil then
		log("handle is nil")
		return
	end
	local result = handle:read("*a")
	handle:close()
	return result
end

---@return string[]
local function get_remote_repos()
	local remote_list_str = exec_bash_command("git remote -v")

	if remote_list_str == nil then
		log("remote list str is nil")
		return {}
	end

	local is_remote_repo_exist = {}

	for remote_name in string.gmatch(remote_list_str, "[^\n]+") do
		local c = 0
		local remote_url = ""

		vim.print(remote_name)

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

	vim.print(remote_repo_list)

	return remote_repo_list
end

---@return string
local function get_current_file_path()
	return vim.fn.expand("%:p")
end

---@param line_no number
---@param file_path string
---@return string|nil
local function get_git_blame_commit_hash(line_no, file_path)
	local command_output = exec_bash_command(string.format("git blame -l -L %d,%d %s", line_no, line_no, file_path))

	if command_output == nil then
		log("Unable to get git blame output")
		return
	end

	for s in string.gmatch(command_output, "%w+") do
		return s
	end
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
			readonly = true,
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

---@param popup popup
---@param pr_description pr_description
local function attach_pr_open_keymap(popup, pr_description)
	vim.api.nvim_buf_set_keymap(popup.bufnr, "n", "<CR>", "", {
		desc = "Open the Pull Request on the browser",
		callback = function()
			exec_bash_command(string.format("gh pr view %s -w", pr_description["url"]))
		end,
	})
end

---@param popup popup
local function highlight_buffer_using_markdown_highlighter(popup)
	vim.api.nvim_set_option_value("filetype", "markdown", { buf = popup.bufnr })
end

---@param pr_url string
---@return string|nil
local function get_pr_details_text(pr_url)
	local pr_details_text = exec_bash_command(string.format("gh pr view %s", pr_url))
	return pr_details_text
end

---@param popup popup
---@param lines string[]
local function write_text_to_popup(popup, lines)
	vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
end

---@param popup popup
---@param pr_details_text string
local function write_pr_description_on_popup(popup, pr_details_text)
	local lines = {}
	for line in string.gmatch(pr_details_text, "[^\r\n]+") do
		table.insert(lines, line)
	end
	write_text_to_popup(popup, lines)
end

---@param commit_hash string
---@return pr_description|nil
local function get_pr_description(commit_hash)
	local remote_repos = get_remote_repos()

	local remote_repos_filter = ""

	for _, remote_repo in ipairs(remote_repos) do
		remote_repos_filter = remote_repos_filter .. string.format("-R %s ", remote_repo)
	end

	local prs_description_output =
		exec_bash_command(string.format('gh search prs "hash:%s" %s--json url,title', commit_hash, remote_repos_filter))

	if prs_description_output == nil then
		log("PR Description output is Null")
		return
	end

	if pcall(vim.json.decode, prs_description_output) then
		local pr_descriptions = vim.json.decode(prs_description_output)
		return pr_descriptions
	end
	return nil
end

function Load_PR_Information()
	local line_no = get_cursor_line_number()
	local commit_hash = get_git_blame_commit_hash(line_no, get_current_file_path())

	if commit_hash == nil then
		log("Unable to get commit_hash")
		return
	end

	local loading_popup = show_popup("Pull Request Loading...")
	attach_popup_close_keymap(loading_popup)

	local pr_descriptions = get_pr_description(commit_hash)

	if pr_descriptions == nil or pr_descriptions[1] == nil then
		loading_popup:unmount()
		return
	end

	local pr_description = pr_descriptions[1]

	local pr_details_text = get_pr_details_text(pr_description["url"])

	if pr_details_text == nil then
		log("Unable to fetch PR details")
		loading_popup:unmount()
		return
	end

	loading_popup:unmount()

	local popup = show_popup(pr_description["title"])
	highlight_buffer_using_markdown_highlighter(popup)
	attach_popup_close_keymap(popup)
	attach_pr_open_keymap(popup, pr_description)
	write_pr_description_on_popup(popup, pr_details_text)
end

