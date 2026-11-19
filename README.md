# Norn for Neovim (`norn.nvim`)

Read a daily Markdown schedule as colour-coded `█` bars in a read-only split. Requires Neovim 0.10 or later. No Obsidian or other plugin dependency.

## Setup

Add this checkout to Neovim’s `runtimepath` in `init.lua`, or load it as a local checkout through your plugin manager. Set the notes directory before the plugin loads.

```lua
vim.opt.runtimepath:prepend(vim.fn.expand("~/path/to/neovim-checkout"))
vim.g.daily_timeline_dir = vim.fn.expand("~/notes/Daily")
```

Replace both paths with yours. If `daily_timeline_dir` is omitted, it defaults to `~/Work/notes/Daily`.

`:DailyTimeline` shows the active `YYYY-MM-DD.md` in the configured directory, or today's note when invoked elsewhere. It uses unsaved buffer contents when available. It does not create or modify notes.

Missing notes and notes without tasks show `No task yet`. Navigation includes every calendar day without creating missing notes.

## Configuring mappings

Set `vim.g.daily_timeline_keymaps` before plugins load. Each entry accepts a key sequence or `false` to disable it. Omitted entries retain their defaults. Set `vim.g.mapleader` before plugins load as usual.

```lua
vim.g.daily_timeline_keymaps = {
  timeline = "<Leader>tg",
  browse = false,
}
```

| Option | Default | Action |
| --- | --- | --- |
| `timeline` | `<Leader>og` | Open the daily timeline |
| `today` | `<Leader>ot` | Open today's note |
| `tomorrow` | `<Leader>on` | Open tomorrow's note |
| `yesterday` | `<Leader>oy` | Open yesterday's note |
| `browse` | `<Leader>od` | Browse daily notes |
| `toggle_checkbox` | `<Leader>oc` | Toggle the current note's checkbox |

Only `timeline` is enabled without Obsidian. For the other actions, set `vim.g.daily_timeline_obsidian = true` before plugins load and add the following to your Obsidian setup options. If you already have an `enter_note` callback, call this function from it instead.

```lua
callbacks = {
  enter_note = require("daily_timeline.keymaps").obsidian_enter_note,
},
```

The checkbox mapping remains buffer-local to Obsidian notes.

If [which-key.nvim](https://github.com/folke/which-key.nvim) is on the runtime path when Daily Timeline loads, the plugin labels its default `<Leader>o` group. Remapped keys and timeline-window controls use standard Neovim descriptions, which which-key reads automatically. No change to your which-key setup is needed; all bindings work without it.

## Notes and controls

```markdown
## Schedule

- [x] 08:00:00 - 08:30:00 | Project: Finished task
- [ ] 09:00 - 10:00 | Project: Planned task
- [ ] Untimed task

## Other tasks

- Follow up on the review
```

Each block represents a 15-minute slot touched by the task; the times at the left are exact. Overlapping tasks occupy separate rows. Untimed items and invalid schedule rows appear below the graph. Same-day ranges only; use `24:00` for an end at midnight. A checked task is marked done, not a measurement of time worked.

Weekly (Monday–Sunday) and monthly views show each date on a shared 15-minute time axis. Bars use the same status colours as the daily view; overlapping bars get extra rows. Untimed items count toward the daily completion total but do not draw bars. Empty days show `No task yet`. Press `Enter` on a date or bar row to open its daily timeline.

The project totals below each view sum exact scheduled durations for the visible day, week, or month. The project is the text before the first colon in `Project: Description`; tasks without it are grouped under `Unassigned`. The second column counts only blocks marked done. Canceled and untimed tasks are excluded. Overlapping blocks are summed separately, so these totals are not a measurement of time worked.

Under each project, indented rows show the same two totals per task description. Descriptions that differ only in capitalization or whitespace are grouped together; the first occurrence supplies the displayed capitalization.

| Key | Action |
| --- | --- |
| `d` / `w` / `m` | Switch to daily / weekly / monthly view |
| `Enter` | Open the selected day, or jump to the source task in daily view |
| `H` / `L` | Move to the previous / next day, week, or month |
| `r` | Refresh from the source |
| `q` | Close the view |

## Theme colours

| State | Highlight group | Default link |
| --- | --- | --- |
| Open `[ ]` | `DailyTimelineOpen` | `DiagnosticInfo` |
| Done `[x]` | `DailyTimelineDone` | `DiagnosticOk` |
| Waiting `[?]` | `DailyTimelineWaiting` | `DiagnosticWarn` |
| Canceled `[-]` | `DailyTimelineCanceled` | `Comment` |

The default links follow the active colourscheme and are restored on [`ColorScheme`](https://neovim.io/doc/user/autocmd/#ColorScheme). To override a link, define your own highlight after loading your theme and in a `ColorScheme` callback if you switch themes during a session:

```lua
vim.api.nvim_set_hl(0, "DailyTimelineDone", { link = "String" })
```

## Checks

From the plugin directory, run in Bash or Fish:

```sh
nvim --headless --clean -n -i NONE -l tests/integration.lua
```
