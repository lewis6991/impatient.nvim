local M = {}

local function printf(msg, ...)
  print(string.format(msg, ...))
end

function M.print_profile(profile)
  if not profile then
    print('Error: profiling was not enabled')
    return
  end

  local total_resolve = 0
  local total_load = 0

  local profile_sorted = {}

  local name_pad = 0
  for k, p in pairs(profile) do
    p.resolve = p.resolve / 1000000
    p.load    = p.load / 1000000

    total_resolve = total_resolve + p.resolve
    total_load = total_load + p.load
    p.module = k
    if #k > name_pad then
      name_pad = #k
    end
    p.total = p.resolve + p.load
    profile_sorted[#profile_sorted+1] = p
  end

  table.sort(profile_sorted, function(a, b)
    return a.total > b.total
  end)

  printf('%-'..name_pad..'s │ Resolve    │ Load       │ Total      │', 'Module')
  printf('%s │ ---------- │ ---------- │ ---------- │', string.rep('-', name_pad))
  for _, p in pairs(profile_sorted) do
    printf('%-'..name_pad..'s │ %8.4fms │ %8.4fms │ %8.4fms │', p.module, p.resolve, p.load, p.total)
  end
  printf('%s │ ---------- │ ---------- │ ---------- │', string.rep('-', name_pad))
  printf('%-'..name_pad..'s │ %8.4fms │ %8.4fms │ %8.4fms │', 'Total', total_load, total_load, total_load+total_load)

end

return M
