# diff-navigator

A Neovim plugin for navigating git diff hunks. Jump between local (unstaged) changes or remote (vs origin) changes with ease.

## Features

- Navigate through **local diff hunks** (unstaged changes)
- Navigate through **remote diff hunks** (changes compared to a remote branch)
- Automatic highlighting of the current hunk
- Wraps around when reaching the end/beginning of hunks
- Configurable keymaps and highlight duration

## Installation

### lazy.nvim

```lua
{
  "alexandrelam/diff-navigator.nvim",
  config = function()
    require("diff-navigator").setup()
  end,
}
```

### packer.nvim

```lua
use {
  "alexandrelam/diff-navigator.nvim",
  config = function()
    require("diff-navigator").setup()
  end,
}
```

### vim-plug

```vim
Plug 'alexandrelam/diff-navigator.nvim'

" In your init.lua or after plugin loads:
lua require("diff-navigator").setup()
```

## Configuration

```lua
require("diff-navigator").setup({
  -- Highlight duration in milliseconds
  highlight_duration = 1500,

  -- Remote branch for remote diff comparison
  remote_branch = "origin/main",

  -- Keymaps (set to false to disable all default keymaps)
  keymaps = {
    local_next = "<leader>gj",
    local_prev = "<leader>gk",
    remote_next = "<leader>gl",
    remote_prev = "<leader>gh",
  },
})
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `highlight_duration` | number | `1500` | Duration in ms to highlight the current hunk |
| `remote_branch` | string | `"origin/main"` | Remote branch for comparison |
| `keymaps` | table/false | see below | Keymap configuration or `false` to disable |

### Default Keymaps

| Key | Action |
|-----|--------|
| `<leader>gj` | Jump to next local diff hunk |
| `<leader>gk` | Jump to previous local diff hunk |
| `<leader>gl` | Jump to next remote diff hunk |
| `<leader>gh` | Jump to previous remote diff hunk |

To disable default keymaps and define your own:

```lua
require("diff-navigator").setup({
  keymaps = false,
})

-- Define your own keymaps
vim.keymap.set("n", "]d", require("diff-navigator").local_next)
vim.keymap.set("n", "[d", require("diff-navigator").local_prev)
```

## Commands

| Command | Description |
|---------|-------------|
| `:DiffNavLocalNext` | Jump to next local diff hunk |
| `:DiffNavLocalPrev` | Jump to previous local diff hunk |
| `:DiffNavRemoteNext` | Jump to next remote diff hunk |
| `:DiffNavRemotePrev` | Jump to previous remote diff hunk |

## API

The plugin exposes these functions for programmatic use:

```lua
local dn = require("diff-navigator")

dn.local_next()   -- Navigate to next local hunk
dn.local_prev()   -- Navigate to previous local hunk
dn.remote_next()  -- Navigate to next remote hunk
dn.remote_prev()  -- Navigate to previous remote hunk
```

## License

MIT
