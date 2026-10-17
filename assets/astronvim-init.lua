-- Stock AstroNvim core; personal configuration remains in the persistent home.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", "https://github.com/folke/lazy.nvim.git", lazypath })
  if vim.v.shell_error ~= 0 then error("Could not bootstrap lazy.nvim") end
end
vim.opt.rtp:prepend(lazypath)
require("lazy").setup({
  { "folke/lazy.nvim", branch = "stable", version = "@LAZY_VERSION@" },
  { "AstroNvim/AstroNvim", version = "@ASTRONVIM_VERSION@", import = "astronvim.plugins", opts = { pin_plugins = true } },
}, {
  concurrency = 4,
  checker = { enabled = false },
  change_detection = { notify = false },
})
