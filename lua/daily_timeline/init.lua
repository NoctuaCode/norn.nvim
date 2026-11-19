local api = vim.api
local schedule = require("daily_timeline.schedule")
local M = {}

local ns = api.nvim_create_namespace("daily_timeline")
local block, slot, hour = "█", 900, 3600
local states = {
  [" "] = { "Open", "DailyTimelineOpen", "DiagnosticInfo" },
  x = { "Done", "DailyTimelineDone", "DiagnosticOk" },
  ["?"] = { "Waiting", "DailyTimelineWaiting", "DiagnosticWarn" },
  ["-"] = { "Canceled", "DailyTimelineCanceled", "Comment" },
}

local function apply_highlights()
  for _, state in pairs(states) do
    api.nvim_set_hl(0, state[2], { default = true, link = state[3] })
  end
end

apply_highlights()
api.nvim_create_autocmd("ColorScheme", {
  group = api.nvim_create_augroup("DailyTimelineHighlights", { clear = true }),
  callback = apply_highlights,
})

local function absolute(path)
  return vim.fs.normalize(vim.fn.fnamemodify(vim.fs.normalize(path), ":p"))
end

local function source_path()
  local dir = absolute(vim.g.daily_timeline_dir or "~/Work/notes/Daily")
  local name = api.nvim_buf_get_name(0)
  if name ~= "" then
    name = absolute(name)
    if vim.fs.dirname(name) == dir and vim.fs.basename(name):match("^%d%d%d%d%-%d%d%-%d%d%.md$") then
      return name
    end
  end
  return vim.fs.joinpath(dir, os.date("%Y-%m-%d") .. ".md")
end

local function date_parts(path)
  local year, month, day = vim.fs.basename(path):match("^(%d+)%-(%d+)%-(%d+)%.md$")
  return tonumber(year), tonumber(month), tonumber(day)
end

local function date_path(path, year, month, day)
  -- Normalize calendar fields at local noon rather than adding seconds across DST.
  local date = os.time({ year = year, month = month, day = day, hour = 12 })
  return vim.fs.joinpath(vim.fs.dirname(path), os.date("%Y-%m-%d", date) .. ".md"), date
end

local function adjacent_path(path, offset, view)
  local year, month, day = date_parts(path)
  if view == "month" then
    return date_path(path, year, month + offset, 1)
  end
  return date_path(path, year, month, day + offset * (view == "week" and 7 or 1))
end

local function source_buffer(path)
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_get_name(buf) == path then
      return buf
    end
  end
end

local function source_lines(path)
  local buf = source_buffer(path)
  if buf and api.nvim_buf_is_loaded(buf) then
    return api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  if vim.fn.filereadable(path) == 0 then
    local _, _, code = vim.uv.fs_stat(path)
    if code == "ENOENT" then
      return {}
    end
    return nil, "No readable daily note: " .. path
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if ok then
    return lines
  end
  return nil, "Could not read daily note: " .. path
end

local function state_label(task)
  if task.state then
    return states[task.state] and states[task.state][1] or ("[" .. task.state .. "]")
  end
  return ""
end

local function time_axis(first, last, width, prefix)
  local axis = { string.rep(" ", prefix) }
  for tick = first, last - hour, hour do
    axis[#axis + 1] = ("%02d"):format(tick / hour) .. string.rep(" ", 4 * width - 2)
  end
  return table.concat(axis) .. ("%02d"):format(last / hour)
end

local function render_timed(timed, lines, rows, highlights)
  local first = math.floor(timed[1].start_time / hour) * hour
  local last = first
  for _, task in ipairs(timed) do
    last = math.max(last, task.end_time)
  end
  last = math.ceil(last / hour) * hour

  -- Keep screen cell widths separate from the byte offsets Neovim extmarks use.
  local width = vim.fn.strdisplaywidth(block)
  lines[#lines + 1] = time_axis(first, last, width, 19)

  for _, task in ipairs(timed) do
    local start_slot = math.floor((task.start_time - first) / slot)
    local end_slot = math.ceil((task.end_time - first) / slot)
    local prefix = ("%-17s  "):format(task.range) .. string.rep(" ", start_slot * width)
    local bar = block:rep(end_slot - start_slot)
    local suffix = string.rep(" ", ((last - first) / slot - end_slot) * width)
    local row = #lines + 1
    lines[row] = prefix .. bar .. suffix .. ("  │ %-8s  %s"):format(state_label(task), task.label)
    rows[row] = task
    local state = states[task.state]
    if state then
      highlights[#highlights + 1] = { row - 1, #prefix, #prefix + #bar, state[2] }
    end
  end
end

local function add_project_time(totals, task)
  if task.state == "-" then
    return
  end
  local prefix, description = task.label:match("^([^:]+):(.*)$")
  local project = prefix and vim.trim(prefix) or ""
  if project == "" then
    project = "Unassigned"
  end
  local total = totals[project]
  if not total then
    total = { scheduled = 0, done = 0, tasks = {} }
    totals[project] = total
  end
  local duration = task.end_time - task.start_time
  local label = (vim.trim(description or task.label):gsub("%s+", " "))
  if label == "" then
    label = "(No description)"
  end
  local key = vim.fn.tolower(label)
  local detail = total.tasks[key]
  if not detail then
    detail = { label = label, scheduled = 0, done = 0 }
    total.tasks[key] = detail
  end
  detail.scheduled = detail.scheduled + duration
  total.scheduled = total.scheduled + duration
  if task.state == "x" then
    total.done = total.done + duration
    detail.done = detail.done + duration
  end
end

local function format_duration(seconds)
  return ("%02d:%02d:%02d"):format(math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
end

local function render_project_totals(lines, totals)
  local projects = vim.tbl_keys(totals)
  if #projects == 0 then
    return
  end
  table.sort(projects)
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Project time (scheduled / marked done)"
  for _, project in ipairs(projects) do
    local total = totals[project]
    lines[#lines + 1] = ("  %s / %s  %s"):format(
      format_duration(total.scheduled), format_duration(total.done), project
    )
    local tasks = vim.tbl_keys(total.tasks)
    table.sort(tasks)
    for index, key in ipairs(tasks) do
      local detail = total.tasks[key]
      lines[#lines + 1] = ("    %s %s / %s  %s"):format(
        index == #tasks and "└─" or "├─",
        format_duration(detail.scheduled), format_duration(detail.done), detail.label
      )
    end
  end
end

local function render_overview(path, view, lines, rows, highlights, totals)
  local year, month, day = date_parts(path)
  local first, count
  if view == "week" then
    local _, date = date_path(path, year, month, day)
    first = day - (tonumber(os.date("%w", date)) + 6) % 7
    count = 7
    local monday = date_path(path, year, month, first)
    lines[1] = "Weekly timeline · week of " .. vim.fs.basename(monday):sub(1, -4)
  else
    first = 1
    local _, last = date_path(path, year, month + 1, 0)
    count = tonumber(os.date("%d", last))
    lines[1] = ("Monthly timeline · %04d-%02d"):format(year, month)
  end
  local days, start_time, end_time = {}, math.huge, 0
  for offset = 0, count - 1 do
    local day_path, date = date_path(path, year, month, first + offset)
    local source = source_lines(day_path)
    local timed, untimed = {}, {}
    local summary = "Could not read daily note"
    if source then
      timed, untimed = schedule.parse(source)
      local total, done = #timed + #untimed, 0
      for _, task in ipairs(timed) do
        start_time = math.min(start_time, task.start_time)
        end_time = math.max(end_time, task.end_time)
        done = done + (task.state == "x" and 1 or 0)
        add_project_time(totals, task)
      end
      for _, task in ipairs(untimed) do
        done = done + (task.state == "x" and 1 or 0)
      end
      summary = total == 0 and "No task yet" or ("%d/%d done"):format(done, total)
    end
    days[#days + 1] = { path = day_path, label = os.date("%Y-%m-%d", date), timed = timed, summary = summary }
  end

  lines[2] = ""
  local width = vim.fn.strdisplaywidth(block)
  local has_bars = end_time > 0
  local start = has_bars and math.floor(start_time / hour) * hour or 0
  local finish = math.ceil(end_time / hour) * hour
  local slots = (finish - start) / slot
  local indent = 12
  if has_bars then
    lines[#lines + 1] = time_axis(start, finish, width, indent)
  end
  for _, entry in ipairs(days) do
    local lanes = { { tail = 0, text = entry.label .. "  " } }
    for _, task in ipairs(entry.timed) do
      local left = math.floor((task.start_time - start) / slot)
      local right = math.ceil((task.end_time - start) / slot)
      local lane_idx = 1
      -- Pack by rendered cells so rounding cannot hide a neighbouring task.
      while lanes[lane_idx] and lanes[lane_idx].tail > left do
        lane_idx = lane_idx + 1
      end
      local lane = lanes[lane_idx] or { tail = 0, text = string.rep(" ", indent) }
      lanes[lane_idx] = lane
      local prefix = lane.text .. string.rep(" ", (left - lane.tail) * width)
      lane.text = prefix .. block:rep(right - left)
      lane.tail = right
      local state = states[task.state]
      if state then
        highlights[#highlights + 1] = { #lines + lane_idx - 1, #prefix, #lane.text, state[2] }
      end
    end
    for idx, lane in ipairs(lanes) do
      local row = #lines + 1
      lines[row] = lane.text
      if idx == 1 then
        lines[row] = lane.text .. string.rep(" ", (slots - lane.tail) * width) .. "  │ " .. entry.summary
      end
      rows[row] = entry.path
    end
  end
  if has_bars then
    local legend = ""
    for _, key in ipairs({ " ", "x", "?", "-" }) do
      local state = states[key]
      highlights[#highlights + 1] = { #lines, #legend, #legend + #block, state[2] }
      legend = legend .. block .. " " .. state[1] .. "  "
    end
    lines[#lines + 1] = legend
  end
end

local function render_day(path, lines, rows, highlights, totals)
  lines[1] = "Daily timeline · " .. vim.fs.basename(path):sub(1, -4)
  lines[2] = ""
  local source, err = source_lines(path)
  if not source then
    lines[#lines + 1] = err
  else
    local timed, untimed = schedule.parse(source)
    if #timed > 0 then
      render_timed(timed, lines, rows, highlights)
      for _, task in ipairs(timed) do
        add_project_time(totals, task)
      end
    elseif #untimed == 0 then
      lines[#lines + 1] = "No task yet"
    else
      lines[#lines + 1] = "No timed tasks."
    end
    if #untimed > 0 then
      lines[#lines + 1] = ""
      lines[#lines + 1] = "Untimed tasks"
      for _, task in ipairs(untimed) do
        local row = #lines + 1
        local label = state_label(task)
        local prefix = label == "" and "" or (label .. "  ")
        local warning = task.invalid and "Invalid schedule: " or ""
        lines[row] = "  " .. prefix .. warning .. task.label
        rows[row] = task
      end
    end
  end
end

local function refresh(buf, path, view)
  local lines, rows, highlights, totals = {}, {}, {}, {}
  if view == "day" then
    render_day(path, lines, rows, highlights, totals)
  else
    render_overview(path, view, lines, rows, highlights, totals)
  end
  render_project_totals(lines, totals)
  lines[#lines + 1] = ""
  lines[#lines + 1] = "d: day   w: week   m: month   H/L: previous/next   Enter: open   r: refresh   q: close"

  vim.bo[buf].modifiable = true
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  for _, span in ipairs(highlights) do
    api.nvim_buf_set_extmark(buf, ns, span[1], span[2], { end_col = span[3], hl_group = span[4] })
  end
  vim.bo[buf].modified = false
  vim.bo[buf].modifiable = false
  return rows
end

local function jump(path, task)
  if not task then
    return
  end
  local buf = source_buffer(path)
  if not (buf and api.nvim_buf_is_loaded(buf)) then
    if vim.fn.filereadable(path) == 0 then
      vim.notify("Daily note is no longer readable: " .. path, vim.log.levels.WARN)
      return
    end
    buf = buf or vim.fn.bufadd(path)
    local ok = pcall(vim.fn.bufload, buf)
    if not ok or not api.nvim_buf_is_loaded(buf) then
      vim.notify("Could not open daily note: " .. path, vim.log.levels.WARN)
      return
    end
  end
  if api.nvim_buf_get_lines(buf, task.row - 1, task.row, false)[1] ~= task.source then
    vim.notify("Daily note changed. Press r to refresh the timeline.", vim.log.levels.WARN)
    return
  end
  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    win = api.nvim_get_current_win()
    api.nvim_win_set_buf(win, buf)
  else
    api.nvim_set_current_win(win)
  end
  api.nvim_win_set_cursor(win, { task.row, 0 })
  vim.cmd.normal({ args = { "zv" }, bang = true })
end

function M.open()
  local path = source_path()
  local view = "day"
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  local rows = refresh(buf, path, view)
  local win = api.nvim_open_win(buf, true, { split = "below", win = 0 })
  local wo = vim.wo[win]
  wo.wrap, wo.number, wo.relativenumber, wo.list = false, false, false, false
  wo.foldenable, wo.signcolumn, wo.statuscolumn = false, "no", ""

  local opts = { buffer = buf, nowait = true }
  local function bind(key, desc, action)
    vim.keymap.set("n", key, action, vim.tbl_extend("force", opts, { desc = desc }))
  end
  local function redraw()
    rows = refresh(buf, path, view)
    if view ~= "day" then
      for row, day_path in pairs(rows) do
        if day_path == path then
          api.nvim_win_set_cursor(win, { row, 0 })
          return
        end
      end
    end
    api.nvim_win_set_cursor(win, { 1, 0 })
  end

  for key, target in pairs({ d = "day", w = "week", m = "month" }) do
    bind(key, "Show " .. target .. " view", function()
      local selected = view ~= "day" and rows[api.nvim_win_get_cursor(win)[1]]
      path = selected or path
      view = target
      redraw()
    end)
  end
  bind("<CR>", "Open day or source task", function()
    local selected = rows[api.nvim_win_get_cursor(win)[1]]
    if view == "day" then
      jump(path, selected)
    elseif selected then
      path, view = selected, "day"
      redraw()
    end
  end)
  bind("r", "Refresh timeline", function()
    rows = refresh(buf, path, view)
  end)
  local function move_period(offset)
    path = adjacent_path(path, offset, view)
    redraw()
  end
  bind("H", "Previous period", function()
    move_period(-1)
  end)
  bind("L", "Next period", function()
    move_period(1)
  end)
  bind("q", "Close timeline", function()
    if vim.fn.winnr("$") == 1 then
      vim.cmd.enew()
    else
      vim.cmd.close()
    end
  end)
end

return M
