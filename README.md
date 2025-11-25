# csub.nvim

Edit the current quickfix list in a scratch buffer. Write the buffer to push the updates back into the original files and quickfix list.

**Example use cases:**

- Use as a replacement for `:cfdo` and `:cdo`(Find and replace across multiple files)
    - Unlike `:cfdo` or `:cdo`, you can see all changes in context before applying them. 
- Edit the `Csub` buffer as if you would any other buffer and all changes will be applied atomically when you write the buffer.

## Features
- Opens the quickfix list in an editable buffer (`[csub]`, `filetype=csub`)
- Shows file/line/col metadata as virtual text beside each entry
- Protects the line count to keep quickfix entries aligned
- Run `:Csub` switch back and forth between the quickfix list and the csub buffer

## Installation

vim.pack example (Neovim 0.12+):
```lua
vim.pack.add({"https://github.com/anoopkcn/csub.nvim"})
require("csub").setup()
```

Lazy.nvim example:
```lua
{
  "https://github.com/anoopkcn/csub.nvim",
  config = function()
    require("csub").setup()
  end,
}
```

Packer.nvim example:
```lua
use({
  "https://github.com/anoopkcn/csub.nvim",
  config = function()
    require("csub").setup()
  end,
})
```

## Usage
1. Populate a quickfix list (e.g. `:make`, `:grep`, diagnostics).
2. Run `:Csub` to open the list in the existing quickfix window for editing.
3. Edit the lines directly; keep the line count unchanged.
4. Write (`:w`) to apply changes back to the underlying files and quickfix list; the view jumps back to the quickfix list.

**NOTE: closing the csub buffer without writing discards all changes.**

Useful keymap:
```lua
vim.keymap.set("n", "<leader>s", "<cmd>Csub<cr>", { desc = "Csub the current quickfix" })
```

## Options

- `g:csub_no_save`: when non-zero and `'hidden'` is set, avoid saving modified buffers when applying changes (leave them listed and modified). Default: 0.

## Notes
- Metadata is virtual text; wrapping is disabled locally.
- If the target line changed since the quickfix list was built and differs from your edit, the plug-in reports an error and leaves that entry untouched.

## Help

Run `:help csub` after installing (requires `:helptags doc`).
