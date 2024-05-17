local function get_cursor_line_number()
	local r, _ = unpack(vim.api.nvim_win_get_cursor(0))
	return r
end

local function log(line)
	local f = io.open("./pr.log", "a+")
	io.write(line)
	io.close(f)
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

local function get_pr_title_and_url()
	local line_no = get_cursor_line_number()
	local commit_hash = get_git_blame_commit_hash(line_no, get_current_file_path())
	local prs_description_output =
		exec_bash_command(string.format('gh search prs "hash:%s" --json url --json title', commit_hash))

	if prs_description_output == nil then
		log("PR Description output is Null")
		return
	end

	local pr_description = vim.json.decode(prs_description_output)
	return pr_description
end

vim.keymap.set("n", "<leader>pr", function()
	local pr_description = get_pr_title_and_url()
	log(vim.json.encode(pr_description))
	vim.print(pr_description)
end, { desc = "Get Pull Request Information" })
