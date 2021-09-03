local M = {}

local api = vim.api

function M.print_profile(profile)
  if not profile then
    print('Error: profiling was not enabled')
    return
  end

  local total_resolve = 0
  local total_load = 0
  local name_pad = 0
  local profile_sorted = {}

  for module, p in pairs(profile) do
    p.resolve = p.resolve / 1000000
    p.load    = p.load / 1000000
    p.total   = p.resolve + p.load
    p.module  = module

    total_resolve = total_resolve + p.resolve
    total_load   = total_load + p.load

    if #module > name_pad then
      name_pad = #module
    end

    profile_sorted[#profile_sorted+1] = p
  end

  table.sort(profile_sorted, function(a, b)
    return a.total > b.total
  end)

  local lines = {}
  local function add(...)
    lines[#lines+1] = string.format(...)
  end

  add('%-'..name_pad..'s │ Resolve    │ Load       │ Total      │', 'Module')
  add('%s │ ---------- │ ---------- │ ---------- │', string.rep('-', name_pad))
  add('%-'..name_pad..'s │ %8.4fms │ %8.4fms │ %8.4fms │', 'Total', total_resolve, total_load, total_resolve+total_load)
  add('%s │ ---------- │ ---------- │ ---------- │', string.rep('-', name_pad))
  for _, p in pairs(profile_sorted) do
    add('%-'..name_pad..'s │ %8.4fms │ %8.4fms │ %8.4fms │', p.module, p.resolve, p.load, p.total)
  end

  local bufnr = api.nvim_create_buf(false, false)
  api.nvim_buf_set_lines(bufnr, 0, 0, false, lines)
  api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
  api.nvim_buf_set_name(bufnr, 'Impatient Profile Report')
  api.nvim_set_current_buf(bufnr)
end

return M
