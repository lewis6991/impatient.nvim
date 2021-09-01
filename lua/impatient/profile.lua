local M = {}

local function printf(msg, ...)
  print(string.format(msg, ...))
end

function M.print_profile(profile)
  if not profile then
    print('Error: profiling was not enabled')
    return
  end

  local total_load = 0
  local total_exec = 0

  local profile_sorted = {}

  local name_pad = 0
  for k, p in pairs(profile) do
    p.resolve = p.resolve / 1000000
    p.execute = p.execute / 1000000

    total_load = total_load + p.resolve
    total_exec = total_exec + p.execute
    p.module = k
    if #k > name_pad then
      name_pad = #k
    end
    p.total = p.resolve + p.execute
    profile_sorted[#profile_sorted+1] = p
  end

  table.sort(profile_sorted, function(a, b)
    return a.total > b.total
  end)

  printf('%-'..name_pad..'s │ Resolve    │ Execute    │ Total      │', 'Module')
  printf('%s │ ---------- │ ---------- │ ---------- │', string.rep('-', name_pad))
  for _, p in pairs(profile_sorted) do
    printf('%-'..name_pad..'s │ %8.4fms │ %8.4fms │ %8.4fms │', p.module, p.resolve, p.execute, p.total)
  end
  printf('%s │ ---------- │ ---------- │ ---------- │', string.rep('-', name_pad))
  printf('%-'..name_pad..'s │ %8.4fms │ %8.4fms │ %8.4fms │', 'Total', total_load, total_exec, total_load+total_exec)

end

return M
