# csub.nvim

Edit the current quickfix or location list in a scratch buffer. Write the buffer to push the updates back into the original files and the list.

## Features
- Opens a quickfix or location list in an editable buffer (`[csub]`, `filetype=csub`)
- Works on whichever list (quickfix or loclist) you invoke `:Csub` from
- Shows a plain `path:line:col` label beside each entry in the `[csub]` buffer (virtual text, aligned to one gutter)
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

The plugin works out of the box — no `setup()` call required. The `:Csub` command and the highlight groups are registered automatically at startup by `plugin/csub.lua`; the metadata column appears inside the `[csub]` buffer when you run `:Csub` (csub does not modify the real quickfix/loclist window). By default every list opens in `"replace"` mode; call `setup()` only to configure per-title `handlers` or change the fallback.

vim.pack example (Neovim 0.12+):
```lua
vim.pack.add({"https://github.com/anoopkcn/csub.nvim"})
```

Lazy.nvim example (zero-config):
```lua
{ "https://github.com/anoopkcn/csub.nvim" }
```

Lazy.nvim example (deferred until the first `:Csub` — recommended for true lazy loading):
```lua
{ "https://github.com/anoopkcn/csub.nvim", cmd = { "Csub" } }
```

csub does nothing until `:Csub` is invoked, so loading on the command is enough — there is no startup behavior that needs to run earlier.

Packer.nvim example:
```lua
use({ "https://github.com/anoopkcn/csub.nvim" })
```

## Configuration

`require("csub").setup(opts)` is optional. Out of the box, every list opens in `"replace"` mode. Call `setup()` to register per-title handlers (so buffer pickers get `"buffers"` mode, diagnostics get disabled, etc.) or to change the fallback used for unmatched lists.

```lua
require("csub").setup({
    -- Per-list-title handlers. The first match wins; non-matching lists
    -- fall back to default_mode.
    handlers = {
        { match = "qfbuffers",   mode = "buffers" }, -- buffer picker → close on delete
        { match = "vimgrep",     mode = "replace" }, -- :vimgrep results
        { match = "Diagnostics", mode = nil       }, -- explicitly disable for diagnostics
    },

    -- Fallback for lists that no handler matched. Default: "replace".
    -- Set to nil to disable csub on every unmatched list.
    default_mode = "replace",
})
```

With lazy.nvim:
```lua
{
  "https://github.com/anoopkcn/csub.nvim",
  config = function()
    require("csub").setup({
      handlers = {
        { match = "qfbuffers", mode = "buffers" },
      },
    })
  end,
}
```

### Handlers

Each handler is a `{ match, mode }` table:
- `match`: substring to look for in the list's title (plain text, case-sensitive). Get the title with `vim.fn.getqflist({ title = 1 }).title` (or `getloclist(0, ...)` for a loclist) after running the command that built the list.
- `mode`: one of `"replace"`, `"buffers"`, or `nil`. `nil` explicitly disables csub for that title (useful for diagnostic lists you never want to edit).

Handlers are checked in order; the first match wins. The same handler list is consulted for both quickfix and location lists, so a single handler entry covers `:grep`/`:lgrep`, `:vimgrep`/`:lvimgrep`, etc. when their titles share a substring.

If no handler matches, csub falls back to `default_mode` (default: `"replace"`).

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

If you wan't to only activate the `Csub` command when the quickfix list is open and focused, then use the following autocommand:

```lua
vim.api.nvim_create_autocmd("FileType", {
    pattern = { "qf", "csub" },
    group = vim.api.nvim_create_augroup("CsubQfMap", { clear = true }),
    callback = function(args)
        map("n", "<leader>s", "<CMD>Csub<CR>",
            { buffer = args.buf, silent = true, desc = "Substitute in quickfix (Csub)" })
    end,
})
```

## Highlight groups

| Group               | Default link  | Purpose                                |
|---------------------|---------------|----------------------------------------|
| `CsubMeta`          | `Comment`     | The `path:line:col` metadata label     |
| `CsubDirtyLine`     | `DiffChange`  | `~` sign on edited lines               |

All are `default = true`, so user overrides take precedence.

## Notes
- In the `[csub]` buffer, metadata is virtual text and line wrapping is disabled locally. The real quickfix/loclist window is left untouched.
- Dirty-line `~` signs appear in the sign column for every row whose text differs from its originating entry. The signcolumn auto-shows.
- If the target line changed since the list was built and differs from your edit, the plug-in reports an error and leaves that entry untouched.
- Running `:Csub` with a different range (or no range vs. ranged) on the same list while you have unsaved edits is treated as a context switch and warns; finish or discard the existing buffer first.

## Help

Run `:help csub` after installing (requires `:helptags doc`).
