local api = vim.api
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.g.daily_timeline_dir = vim.fs.joinpath(vim.fn.getcwd(), "tests")
vim.cmd.runtime("plugin/daily_timeline.lua")

local function daily_note(date, lines)
  vim.cmd.enew()
  local buf = api.nvim_get_current_buf()
  api.nvim_buf_set_name(buf, vim.fs.joinpath(vim.g.daily_timeline_dir, date .. ".md"))
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

local function find_row(buf, text)
  for row, line in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:find(text, 1, true) then
      return row, line
    end
  end
end

local function press(key)
  api.nvim_feedkeys(vim.keycode(key), "mx", false)
end

vim.cmd.colorscheme("default")
local source = daily_note("2099-11-19", {
  "# Daily note",
  "## Schedule",
  "- [x] 09:15:00 - 10:00:00 | Team: Résumé",
  "- [ ] 08:00 - 08:30 | Team: early",
  "- [?] 09:30 - 09:45 | Team: overlap",
  "- [-] 10:15 - 10:30 | Team: canceled",
  "- [ ] 08:30 - 08:00 | Team: backwards",
  "- [ ] No time yet",
  "```markdown",
  "- [x] 10:00 - 11:00 | Team: example only",
  "```",
  "## Other tasks",
  "- Follow up",
  "## Notes",
  "- Don't plot this",
})

vim.cmd.DailyTimeline()
local timeline = api.nvim_get_current_buf()
local win = api.nvim_get_current_win()
local early, early_line = find_row(timeline, "Team: early")
local done, done_line = find_row(timeline, "Team: Résumé")
local overlap, overlap_line = find_row(timeline, "Team: overlap")
assert(early and done and overlap and early < done and done < overlap, "Tasks should sort by start time")
assert(early_line:find("██", 1, true) and done_line:find("███", 1, true), "Bars should reflect slot durations")
assert(overlap_line:find("Waiting", 1, true), "Waiting status must remain visible without color")
assert(find_row(timeline, "Canceled  Team: canceled"), "Canceled tasks must have a distinct label")
local untimed = find_row(timeline, "Untimed tasks")
assert(untimed and find_row(timeline, "Invalid schedule: 08:30") > untimed, "Invalid ranges must not enter the plot")
assert(find_row(timeline, "No time yet") > untimed and find_row(timeline, "Follow up") > untimed, "Untimed bullets must remain visible")
assert(not find_row(timeline, "example only") and not find_row(timeline, "Don't plot this"), "Code examples and notes must not appear")
assert(not vim.bo[timeline].modifiable, "The timeline must be read-only")

local marks = api.nvim_buf_get_extmarks(timeline, -1, { done - 1, 0 }, { done - 1, -1 }, { details = true })
assert(#marks == 1, "The done bar should have one highlight span")
local start, details = marks[1][3], marks[1][4]
assert(done_line:sub(start + 1, details.end_col) == "███", "The highlight must cover precisely the Unicode bar")
local group = details.hl_group
local function fg(name)
  return api.nvim_get_hl(0, { name = name, link = false }).fg
end
local initial = fg(group)
assert(initial and initial == fg("DiagnosticOk"), "The done bar must take its color from the theme")
vim.cmd.colorscheme("habamax")
assert(api.nvim_get_current_buf() == timeline and fg(group) == fg("DiagnosticOk") and fg(group) ~= initial,
  "Switching themes must recolor the open timeline")

api.nvim_win_set_cursor(win, { done, 0 })
press("<CR>")
assert(api.nvim_get_current_buf() == source and api.nvim_win_get_cursor(0)[1] == 3,
  "Enter must jump to the source line even after sorting")
api.nvim_buf_set_lines(source, 2, 3, false, { "- [?] 09:15 - 10:00 | Team: updated in memory" })
api.nvim_set_current_win(win)
press("r")
assert(find_row(timeline, "Waiting   Team: updated in memory") and not find_row(timeline, "Team: Résumé"),
  "Refresh must use unsaved buffer edits")
press("q")
assert(not api.nvim_win_is_valid(win) and api.nvim_get_current_buf() == source, "q must close only the timeline window")

vim.bo[source].bufhidden = "hide"
local untimed_source = daily_note("2099-11-20", { "## Schedule", "- [ ] No timestamp" })
vim.cmd.DailyTimeline()
local untimed_view = api.nvim_get_current_buf()
local untimed_row = find_row(untimed_view, "No timestamp")
assert(find_row(untimed_view, "No timed tasks.") and untimed_row and not find_row(untimed_view, "█"),
  "An untimed-only daily note should show its items without a fake graph")
api.nvim_win_set_cursor(0, { untimed_row, 0 })
press("<CR>")
assert(api.nvim_get_current_buf() == untimed_source and api.nvim_win_get_cursor(0)[1] == 2,
  "Untimed tasks should also link to their source")

press("q")
vim.bo[untimed_source].bufhidden = "hide"
daily_note("2099-12-31", { "## Schedule" })
vim.cmd.DailyTimeline()
local day_view = api.nvim_get_current_buf()
assert(find_row(day_view, "No task yet"), "An empty schedule should show the empty state")
press("L")
assert(api.nvim_get_current_buf() == day_view and find_row(day_view, "2100-01-01") and find_row(day_view, "No task yet"),
  "L must cross the year boundary and show a missing day in the same view")
press("H")
assert(find_row(day_view, "2099-12-31") and find_row(day_view, "No task yet"),
  "H must return to the previous calendar day")

press("w")
assert(find_row(day_view, "Weekly timeline · week of 2099-12-28")
  and find_row(day_view, "2100-01-03") and not find_row(day_view, "2100-01-04"),
  "Weekly overview should span Monday through Sunday across the year boundary")
press("L")
assert(find_row(day_view, "Weekly timeline · week of 2100-01-04"), "L should advance by one week")
press("H")
press("m")
assert(find_row(day_view, "Monthly timeline · 2099-12"), "Month view should retain the selected date")
press("L")
assert(find_row(day_view, "Monthly timeline · 2100-01"), "L should advance by one calendar month")
press("H")
press("H")
local selected = find_row(day_view, "2099-11-19")
assert(selected and find_row(day_view, "0/7 done") == selected,
  "Monthly summaries should count tasks from unsaved daily buffers")
assert(find_row(day_view, "01:30:00 / 00:00:00  Team"),
  "Monthly totals must sum overlapping scheduled durations but exclude canceled and untimed tasks")
local function check_overview_bars()
  local row, line = find_row(day_view, "2099-11-19")
  local overlap = api.nvim_buf_get_lines(day_view, row, row + 1, false)[1]
  assert(line:find("███", 1, true) and overlap:match("^ +█$"),
    "Overlapping time blocks must both remain visible on separate lanes")
  local marks = api.nvim_buf_get_extmarks(day_view, -1, { row, 0 }, { row, -1 }, { details = true })
  assert(#marks == 1 and marks[1][4].hl_group == "DailyTimelineWaiting",
    "The overlapping bar must keep its task status highlight")
end
check_overview_bars()
api.nvim_win_set_cursor(0, { selected, 0 })
press("w")
check_overview_bars()
assert(find_row(day_view, "01:30:00 / 00:00:00  Team"), "Weekly view should show project totals")
selected = find_row(day_view, "2099-11-19") + 1
api.nvim_win_set_cursor(0, { selected, 0 })
press("<CR>")
assert(find_row(day_view, "Daily timeline · 2099-11-19") and find_row(day_view, "updated in memory"),
  "Enter should open the selected day's timeline in the same buffer")
assert(find_row(day_view, "01:30:00 / 00:00:00  Team"), "Daily view should show project totals")

press("q")
vim.bo[source].bufhidden = "hide"
daily_note("2099-12-30", {
  "## Schedule",
  "- [x] 08:00 - 08:15 | Alpha: Review PR",
  "- [ ] 08:15 - 08:45 | Alpha: review   pr",
  "- [-] 08:45 - 09:45 | Alpha: REVIEW PR",
  "- [x] 09:45 - 10:00 | Beta: review pr",
})
vim.cmd.DailyTimeline()
local detail_view = api.nvim_get_current_buf()
local alpha = find_row(detail_view, "00:45:00 / 00:15:00  Alpha")
local beta = find_row(detail_view, "00:15:00 / 00:15:00  Beta")
assert(alpha and beta == alpha + 2, "Alpha's matching descriptions should collapse into one child")
assert(find_row(detail_view, "└─ 00:45:00 / 00:15:00  Review PR") == alpha + 1,
  "The child must combine case and whitespace variants without counting the canceled block")
assert(find_row(detail_view, "└─ 00:15:00 / 00:15:00  review pr") == beta + 1,
  "Matching descriptions in different projects must stay separate")

print("Daily Timeline integration scenarios passed")
