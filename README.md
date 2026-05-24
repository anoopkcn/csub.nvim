# csub.nvim

Edit the current quickfix or location list in a scratch buffer. Write the buffer to push the updates back into the original files and the list.

## Features
- Opens a quickfix or location list in an editable buffer (`[csub]`, `filetype=csub`)
- Works on whichever list (quickfix or loclist) you invoke `:Csub` from
- Shows file/line/col metadata as virtual text beside each entry
- Marks edited lines with a `~` sign in the sign column so changes are visible at a glance
- Applies changes to the underlying files and the list on write
- Run `:Csub` to switch back and forth between the list window and the csub buffer
- Use a range — `:'<,'>Csub` or `:3,7Csub` — to scope editing to a slice of the list; entries outside the range round-trip unchanged
- Supports different modes based on quickfix source (text replacement, buffer management)

**Example: Find and Replace**
- Use as a replacement for `:cfdo` and `:cdo`(Find and replace across multiple files)
    - Unlike `:cfdo` or `:cdo`, you can make arbitrary changes and see the results before applying them.
- Edit the `Csub` buffer as if you would any other buffer and all changes will be applied when you write the buffer.
- Saving(`:w`) the Csub buffer will switch back to the updated quickfix list.

**Example: Buffer Management**
- Configure csub to close buffers when using a buffer picker that populates the quickfix list
- Delete lines in the csub buffer to close the corresponding buffers

**Example: Location lists**
- `:lvimgrep /pattern/ %`, open the loclist with `:lopen`, then `:Csub` from inside the loclist window.
- Edits apply to the owner window's location list; the quickfix list is left untouched.

**Example: Scoped editing**
- `:5,10Csub` opens only entries 5–10 in the csub buffer. The other entries stay put.
- Visual-line select rows in the list window and run `:Csub` — same effect with the visual range.

## Requirements
- Neovim 0.12 or higher
- Verified with Neovim 0.12.1

## Installation

The plugin works out of the box — no `setup()` call required. The `:Csub` command, the list metadata column, and the highlight groups are registered automatically at startup by `plugin/csub.lua`.

vim.pack example (Neovim 0.12+):
```lua
vim.pack.add({"https://github.com/anoopkcn/csub.nvim"})
```

Lazy.nvim example (zero-config):
```lua
{ "https://github.com/anoopkcn/csub.nvim" }
```

Lazy.nvim example (deferred until the first quickfix command — recommended for true lazy loading):
```lua
{ "https://github.com/anoopkcn/csub.nvim", event = "QuickFixCmdPre" }
```

`cmd = { "Csub" }` is also possible, but with that trigger any quickfix list opened before the first `:Csub` will not get csub's metadata column — the plugin's `quickfixtextfunc` only takes effect once it's loaded.

Packer.nvim example:
```lua
use({ "https://github.com/anoopkcn/csub.nvim" })
```

## Configuration

`require("csub").setup(opts)` is optional. Call it only if you want to override the defaults:

```lua
require("csub").setup({
    -- Handlers to detect mode based on quickfix title
    handlers = {
        { match = "FuzzyBuffers", mode = "buffers" },
        { match = "Grep",         mode = "replace" },
        { match = "vimgrep",      mode = "replace" },
        { match = "Diagnostics",  mode = nil       }, -- disable csub
    },

    -- Fallback mode when no handler matches (default: "replace")
    default_mode = "replace",
})
```

With lazy.nvim, the usual wiring works:
```lua
{
  "https://github.com/anoopkcn/csub.nvim",
  config = function()
    require("csub").setup({ default_mode = "buffers" })
  end,
}
```

### Handlers

Handlers allow csub to behave differently based on what command created the list. Each handler has:
- `match`: A string to match against the list title (plain text match against the quickfix or loclist title)
- `mode`: The mode to use when matched

### Modes

| Mode | Delete line | Edit text | Add line | Use case |
|------|-------------|-----------|----------|----------|
| `"replace"` | Remove from list | Replace line in file | Rejected | Grep results, compiler errors |
| `"buffers"` | Close buffer (`:bdelete`) | Ignored | Rejected | Buffer pickers |
| `nil` | - | - | - | Disable csub for this list |

**Notes:**
- In `"buffers"` mode, use `:w!` to force-close modified buffers
- The mode is detected from the list title when `:Csub` is invoked
- The same handler list is checked for both quickfix and location lists

## Usage
1. Populate a quickfix or location list (e.g. `:make`, `:grep`, `:lvimgrep`, diagnostics, a file picker).
2. Run `:Csub` from inside the list window (quickfix or loclist) to open it for editing in place.
   - Add a range to scope the edit: `:5,10Csub` or `:'<,'>Csub` opens only those entries; the rest round-trip unchanged on write.
3. Edit the lines directly. Edited rows are marked with a `~` sign in the sign column. Deleting a line removes that entry. Adding lines is rejected.
4. Run `:Csub` again at any point to toggle back to the list window without discarding unsaved edits.
5. Write (`:w`) to apply changes back to the underlying files and the list; the view jumps back to the list window.

**NOTE: closing the csub buffer without writing discards all changes.**

Useful keymap:
```lua
vim.keymap.set("n", "<leader>s", "<cmd>Csub<cr>", { desc = "Csub the current list" })
vim.keymap.set("x", "<leader>s", ":Csub<cr>",     { desc = "Csub the selected entries" })
```

## Highlight groups

| Group               | Default link  | Purpose                                |
|---------------------|---------------|----------------------------------------|
| `CsubMetaFileName`  | `Comment`     | File-name portion of the metadata col  |
| `CsubMetaNumber`    | `Number`      | Line/column numbers in the metadata    |
| `CsubSeparator`     | `Comment`     | `|` separators in the metadata         |
| `CsubDirtyLine`     | `DiffChange`  | `~` sign on edited lines               |

All are `default = true`, so user overrides take precedence.

## Notes
- Metadata is virtual text; line wrapping is disabled locally.
- Dirty-line `~` signs appear in the sign column for every row whose text differs from its originating entry. The signcolumn auto-shows.
- If the target line changed since the list was built and differs from your edit, the plug-in reports an error and leaves that entry untouched.
- Running `:Csub` with a different range (or no range vs. ranged) on the same list while you have unsaved edits is treated as a context switch and warns; finish or discard the existing buffer first.

## Help

Run `:help csub` after installing (requires `:helptags doc`).
