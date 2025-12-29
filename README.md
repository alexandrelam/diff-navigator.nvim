# diff-navigator

A Neovim plugin for navigating git diff hunks. Jump between local (unstaged) changes or remote (vs origin) changes with ease.

## Features

- Navigate through **local diff hunks** (unstaged changes)
- Navigate through **remote diff hunks** (changes compared to a remote branch)
- **GitHub CLI integration** - uses `gh pr diff` for PR branches when available
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

  -- Use GitHub CLI (gh pr diff) when available
  use_gh_cli = true,

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
| `use_gh_cli` | boolean | `true` | Use `gh pr diff` for remote diffs when available |
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

### Overriding Keymaps in LazyVim

If you're using LazyVim and have conflicting keybindings, use lazy.nvim's `keys` spec to ensure your keymaps take precedence:

```lua
{
  "alexandrelam/diff-navigator.nvim",
  keys = {
    { "<leader>gl", function() require("diff-navigator").remote_next() end, desc = "Remote diff: next hunk" },
    { "<leader>gh", function() require("diff-navigator").remote_prev() end, desc = "Remote diff: prev hunk" },
    { "<leader>gj", function() require("diff-navigator").local_next() end, desc = "Local diff: next hunk" },
    { "<leader>gk", function() require("diff-navigator").local_prev() end, desc = "Local diff: prev hunk" },
  },
  opts = {
    keymaps = false, -- Disable built-in keymaps since we're defining them above
  },
}
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

## GitHub CLI Integration

When `use_gh_cli` is enabled (default), the plugin will use `gh pr diff` for remote diffs when:

- The [GitHub CLI](https://cli.github.com/) is installed and authenticated (`gh auth status`)
- The repository's origin is a GitHub remote
- You're on a branch with an open pull request

If any of these conditions are not met, it automatically falls back to `git diff`.

## License

MIT
