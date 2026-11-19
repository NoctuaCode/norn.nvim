local M = {}

local function seconds(value)
  local h, m, s = value:match("^(%d%d):(%d%d):(%d%d)$")
  if not h then
    h, m = value:match("^(%d%d):(%d%d)$")
  end
  h, m, s = tonumber(h), tonumber(m), tonumber(s) or 0
  if not h or m > 59 or s > 59 or h > 24 or (h == 24 and (m ~= 0 or s ~= 0)) then
    return nil
  end
  return h * 3600 + m * 60 + s
end

function M.parse(lines)
  local timed, untimed = {}, {}
  local section, fence
  for row, line in ipairs(lines) do
    local marker, rest = line:match("^ ? ? ?(```+)(.*)$")
    if not marker then
      marker, rest = line:match("^ ? ? ?(~~~+)(.*)$")
    end
    if fence then
      if marker and marker:sub(1, 1) == fence:sub(1, 1) and #marker >= #fence and rest:match("^%s*$") then
        fence = nil
      end
    elseif marker then
      fence = marker
    else
      local heading, title = line:match("^ ? ? ?(#+)%s+(.+)$")
      if heading and #heading <= 2 then
        section = #heading == 2 and vim.trim((title:gsub("%s+#+%s*$", ""))) or nil
      elseif section == "Schedule" or section == "Other tasks" then
        local item = line:match("^%s*[-+*]%s+(.+)$") or line:match("^%s*%d+[.)]%s+(.+)$")
        if item then
          local state, text = item:match("^%[(.)%]%s*(.*)$")
          text = vim.trim(text or item)
          local task = { row = row, source = line, state = state and state:lower(), label = text }
          if section == "Schedule" and text:match("^%d+:") then
            local first, last, label = text:match("^(%S+)%s+%-%s+(%S+)%s*(.*)$")
            local start_time, end_time
            if first then
              start_time, end_time = seconds(first), seconds(last)
              label = vim.trim((label:gsub("^|", "")))
            end
            if start_time and end_time and start_time < end_time and label ~= "" then
              task.start_time, task.end_time = start_time, end_time
              task.range, task.label = first .. "-" .. last, label
              timed[#timed + 1] = task
            else
              task.invalid = true
              untimed[#untimed + 1] = task
            end
          else
            untimed[#untimed + 1] = task
          end
        end
      end
    end
  end
  table.sort(timed, function(a, b)
    if a.start_time == b.start_time then
      return a.row < b.row
    end
    return a.start_time < b.start_time
  end)
  return timed, untimed
end

return M
