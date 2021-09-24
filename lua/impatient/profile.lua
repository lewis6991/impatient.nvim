local M = {}

local api, uv = vim.api, vim.loop

function M.print_profile(profile)
  if not profile then
    print('Error: profiling was not enabled')
    return
  end

  local total_resolve = 0
  local total_load = 0
  local total_exec = 0
  local name_pad = 0
  local modules = {}
  local plugins = {}

  for module, p in pairs(profile) do
    p.load = p.load or 0
    p.resolve = p.resolve or 0
    p.exec = p.exec or 0

    p.resolve = p.resolve / 1000000
    p.load    = p.load / 1000000
    p.exec    = p.exec / 1000000
    p.total   = p.resolve + p.load + p.exec
    p.module  = module:gsub('/', '.')

    local plugin = p.module:match('([^.]+)')
    if plugin then
      if not plugins[plugin] then
        plugins[plugin] = {
          module = plugin,
          resolve = 0,
          load = 0,
          exec = 0,
          total = 0
        }
      end
      local r = plugins[plugin]

      r.resolve = r.resolve + p.resolve
      r.load    = r.load + p.load
      r.exec    = r.exec + p.exec
      r.total   = r.total + p.total

      if not r.loader then
        r.loader = p.loader
      elseif r.loader ~= p.loader then
        r.loader = 'mixed'
      end
    end

    total_resolve = total_resolve + p.resolve
    total_load   = total_load + p.load
    total_exec   = total_exec + p.exec

    if #module > name_pad then
      name_pad = #module
    end

    modules[#modules+1] = p
  end

  table.sort(modules, function(a, b)
    return a.module > b.module
  end)

  do
    local plugins_a = {}
    for _, v in pairs(plugins) do
      plugins_a[#plugins_a+1] = v
    end
    plugins = plugins_a
  end

  table.sort(plugins, function(a, b)
    return a.total > b.total
  end)

  local lines = {}
  local function add(...)
    lines[#lines+1] = string.format(...)
  end

  local l = string.rep('─', name_pad+1)

  add('%s┬───────────┬────────────┬────────────┬────────────┬────────────┐', l)
  add('%-'..name_pad..'s │ Loader    │ Resolve    │ Load       │ Exec       │ Total      │', '')
  add('%s┼───────────┼────────────┼────────────┼────────────┼────────────┤', l)
  add('%-'..name_pad..'s │           │ %8.4fms │ %8.4fms │ %8.4fms │ %8.4fms │', 'Total', total_resolve, total_load, total_exec, total_resolve+total_load+total_exec)
  add('%s┴───────────┴────────────┴────────────┴────────────┴────────────┤', l)
  add('%-'..name_pad..'s                                                                 │', 'By Plugin')
  add('%s┬───────────┬────────────┬────────────┬────────────┬────────────┤', l)
  for _, p in ipairs(plugins) do
    add('%-'..name_pad..'s │ %9s │ %8.4fms │ %8.4fms │ %8.4fms │ %8.4fms │', p.module, p.loader, p.resolve, p.load, p.exec, p.total)
  end
  add('%s┴───────────┴────────────┴────────────┴────────────┴────────────┤', l)
  add('%-'..name_pad..'s                                                                 │', 'By Module')
  add('%s┬───────────┬────────────┬────────────┬────────────┬────────────┤', l)
  for _, p in pairs(modules) do
    add('%-'..name_pad..'s │ %9s │ %8.4fms │ %8.4fms │ %8.4fms │ %8.4fms │', p.module, p.loader, p.resolve, p.load, p.exec, p.total)
  end
  add('%s┴───────────┴────────────┴────────────┴────────────┴────────────┤', l)

  local bufnr = api.nvim_create_buf(false, false)
  api.nvim_buf_set_lines(bufnr, 0, 0, false, lines)
  api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
  api.nvim_buf_set_name(bufnr, 'Impatient Profile Report')
  api.nvim_set_current_buf(bufnr)
end

M.mod_require = function(profile)
  local orig_require = require
  local rp = {}

  require = function(mod)
    local basename = mod:gsub('%.', '/')

    if profile[basename] ~= nil then
      if not profile[basename].loader then
        -- require before profiling was enabled
        profile[basename].loader = 'NA'
      end
      return orig_require(mod)
    end

    -- Only profile the first require
    local pb = {}
    profile[basename] = pb

    rp[#rp+1] = basename
    local ptr = #rp

    local s = uv.hrtime()
    local ret = orig_require(mod)

    pb.exec = uv.hrtime() - s

    -- Remove the execution time for dependent modules
    if #rp > ptr then
      for i = ptr + 1, #rp do
        local dep = rp[i]
        assert(basename ~= dep)
        pb.exec = pb.exec - profile[dep].exec
      end
    end
    assert(pb.exec > 0)

    return ret
  end

  local pl = package.loaders
  for i = 1, #pl do
    local l = pl[i]
    pl[i] = function(mod)
      local basename = mod:gsub('%.', '/')
      local pb = profile[basename]
      if pb and not pb.loader then
        if i == 1 then
          pb.loader = 'preloader'
        else
          pb.loader = '#'..i
        end
      end
      return l(mod)
    end
  end
end

return M
