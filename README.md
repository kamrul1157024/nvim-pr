# nvim-pr

This plugins shows github pull request information of the current line.It will look for the Pull request on the added remote repositories.

## Prerequisite

To use this plugin [gh](https://cli.github.com/) needed to be set up.

## Shortcuts

`<leader>pr`: To see the pull request info of the current line use `<leader>pr`,
`<CR>(Enter)`: To open it on the browser press while cursor on popup. To quit from the popup press `q`.
q: quit from popup

<img width="1231" alt="nvim-pr-screenshot" src="https://github.com/kamrul1157024/nvim-pr/assets/23137328/a2674bd1-a227-4fd3-976c-f2864a69eefa">


## setup:
```lua
{
    "kamrul1157024/nvim-pr",
    config = function()
      require("pr").setup()
    end,
    dependencies = {
      "MunifTanjim/nui.nvim",
    },
  }
```


