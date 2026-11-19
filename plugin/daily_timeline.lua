if vim.g.loaded_daily_timeline then
  return
end
vim.g.loaded_daily_timeline = true

vim.api.nvim_create_user_command("DailyTimeline", function()
  require("daily_timeline").open()
end, { desc = "Show the daily Markdown schedule" })

require("daily_timeline.keymaps").install()
