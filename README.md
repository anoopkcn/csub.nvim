# csub.nvim

Edit the current quickfix list in a scratch buffer, with per-entry metadata so you know what you are changing. Write the buffer to push the updates back into the original files and quickfix list.

## Features
- Opens the quickfix list in an editable buffer (`[csub]`, `filetype=csub`)
- Shows file/line/col metadata as virtual text beside each entry
- Protects the line count to keep quickfix entries aligned
- Warns if target lines changed since the quickfix list was built
- One command to open; optional bang closes quickfix/location list windows after opening

## Installation

vim.pack example (Neovim 0.12+):
```lua
vim.pack.add("akc/csub.nvim")
require("csub").setup()
```

Lazy.nvim example:
```lua
{
  "akc/csub.nvim",
  config = function()
    require("csub").setup()
  end,
}
```

Packer.nvim example:
```lua
use({
  "akc/csub.nvim",
  config = function()
    require("csub").setup()
  end,
})
```

## Usage
1. Populate a quickfix list (e.g. `:make`, `:grep`, diagnostics).
2. Run `:Csub[!] [cmd]`.
   - `[cmd]` controls window creation (`new`, `vnew`, `tabnew`, ...).
   - `!` closes existing quickfix/location list windows after opening the buffer.
3. Edit the lines directly; keep the line count unchanged.
4. Write (`:w`) to apply changes back to the underlying files and quickfix list.

Useful keymap:
```lua
vim.keymap.set("n", "<leader>s", "<cmd>Csub!<cr>", { desc = "Csub the current quickfix" })
```

## Options

- `g:csub_no_save`: when non-zero and `'hidden'` is set, avoid saving modified buffers when applying changes (leave them listed and modified). Default: 0.

## Notes
- Metadata is virtual text; wrapping is disabled locally.
- If the target line changed since the quickfix list was built and differs from your edit, the plugin reports an error and leaves that entry untouched.

## Help

Run `:help csub` after installing (requires `:helptags doc`).
