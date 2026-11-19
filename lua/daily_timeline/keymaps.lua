local M = {}

local function add_which_key_group(obsidian)
  local ok, which_key = pcall(require, "which-key")
  if ok and type(which_key.add) == "function" then
    which_key.add({
      { "<Leader>o", group = obsidian and "Obsidian and daily planning" or "Daily planning" },
    })
  end
end

local function map(action, default, command, desc, buffer)
  local key = (vim.g.daily_timeline_keymaps or {})[action]
  if key == nil then
    key = default
  end
  if key ~= false then
    vim.keymap.set("n", key, "<Cmd>" .. command .. "<CR>", { desc = desc, buffer = buffer })
    return key:lower():sub(1, 9) == "<leader>o"
  end
end

function M.install()
  local obsidian = vim.g.daily_timeline_obsidian == true
  local grouped = map("timeline", "<Leader>og", "DailyTimeline", "Daily timeline")
  if obsidian then
    grouped = map("today", "<Leader>ot", "Obsidian today", "Today's daily plan") or grouped
    grouped = map("tomorrow", "<Leader>on", "Obsidian today 1", "Tomorrow's daily plan") or grouped
    grouped = map("yesterday", "<Leader>oy", "Obsidian today -1", "Yesterday's daily plan") or grouped
    grouped = map("browse", "<Leader>od", "Obsidian dailies", "Browse daily plans") or grouped
    local checkbox = (vim.g.daily_timeline_keymaps or {}).toggle_checkbox
    grouped = grouped or checkbox == nil or (checkbox and checkbox:lower():sub(1, 9) == "<leader>o")
  end
  if grouped then
    add_which_key_group(obsidian)
  end
end

function M.obsidian_enter_note()
  if vim.g.daily_timeline_obsidian == true then
    map("toggle_checkbox", "<Leader>oc", "Obsidian toggle_checkbox", "Toggle task checkbox", true)
  end
end

return M
