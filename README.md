# nvim-pr

This plugins shows github pull request information of the current line.It will look for the Pull request on the added remote repositories.

## Prerequisite

To use this plugin [gh](https://cli.github.com/) needed to be set up.

## Shortcuts


| KeyBinding| cursor   | Mode   | Description                                                 |
|--------------|-------|--------|-------------------------------------------------------------|
|`<CR>(Enter)` | popup | Normal | To open it on the browser press while cursor on the popup.  |
|`q`           | popup | Normal | Quit from popup while cursor on the popup.                  |


## Preview

<img width="1231" alt="nvim-pr-screenshot" src="https://github.com/kamrul1157024/nvim-pr/assets/23137328/a2674bd1-a227-4fd3-976c-f2864a69eefa">


## setup:
```lua
{
  "kamrul1157024/nvim-pr",
  config = function()
    require("nvim-pr").setup()
    vim.keymap.set("n", "<leader>gprv", ":PR open<CR>", { desc = "View PR in the editor" })
    vim.keymap.set("n", "<leader>gprb", ":PR open_in_browser<CR>", { desc = "Open PR in the browser" })
  end,
  dependencies = {
    "MunifTanjim/nui.nvim",
    "nvim-lua/plenary.nvim",
  },
}
```


