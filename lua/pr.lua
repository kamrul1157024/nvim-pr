local Popup = require("nui.popup")
local event = require("nui.utils.autocmd").event

local function get_cursor_line_number()
	local r, _ = unpack(vim.api.nvim_win_get_cursor(0))
	return r
end

local function log(line)
	vim.print(line)
end

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

local function get_remotes()
	local remote_list_str = exec_bash_command("git remote")

	if remote_list_str == nil then
		log("remote list str is nil")
	end

	local remote_list = {}

	for remote_name in string.gmatch(remote_list_str, "[^\n]+") do
		table.insert(remote_list, remote_name)
	end
	return remote_list
end

local function get_repo_name()
	local abs_path = exec_bash_command("git rev-parse --show-toplevel")

	if abs_path == nil then
		log("abs path is nil")
	end
	local last_folder_name = ""
	for folder_name in string.gmatch(abs_path, "[^(/|\n)]+") do
		last_folder_name = folder_name
	end
	return last_folder_name
end

local function get_remote_repos()
	local remotes = get_remotes()
	local repo = get_repo_name()
	local remote_repos = {}
	for _, remote in ipairs(remotes) do
		table.insert(remote_repos, string.format("%s/%s", remote, repo))
	end
	return remote_repos
end

local function get_current_file_path()
	return vim.fn.expand("%:p")
end

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

local function show_popup(pr_description)
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
				top = pr_description["title"],
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

local function attach_key_maps_to_buffer(popup, pr_description)
  vim.api.nvim_buf_set_keymap(popup.bufnr, "n", "<CR>", "", {
		desc = "Open the Pull Request on the browser",
		callback = function()
			exec_bash_command(string.format("gh pr view %s -w", pr_description["url"]))
		end,
	})

	vim.api.nvim_buf_set_keymap(popup.bufnr, "n", "q", "", {
		desc = "Close the popup window",
		callback = function()
			popup:unmount()
		end,
	})
end

local function write_pr_description_on_popup(popup, pr_description)
	local pr_details = exec_bash_command(string.format("gh pr view %s", pr_description["url"]))

	if pr_details == nil then
		log("Unable to fetch PR details")
	end

	local lines = {}
	for line in string.gmatch(pr_details, "[^\r\n]+") do
		table.insert(lines, line)
	end
	vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
end

local function get_pr_title_and_url()
	local line_no = get_cursor_line_number()
	local commit_hash = get_git_blame_commit_hash(line_no, get_current_file_path())
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

vim.keymap.set("n", "<leader>pr", function()
	local pr_descriptions = get_pr_title_and_url()

	if pr_descriptions == nil or pr_descriptions[1] == nil then
		return
	end

	local popup = show_popup(pr_descriptions[1])
  attach_key_maps_to_buffer(popup, pr_descriptions[1])
	write_pr_description_on_popup(popup, pr_descriptions[1])
end, { desc = "Get Pull Request Information" })
