local M = {}

local api, uv = vim.api, vim.loop

local function add_module_to_plugin(plugins, m)
  local plugin = m.module:match('([^.]+)')
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
    local p = plugins[plugin]

    p.resolve = p.resolve + m.resolve
    p.load    = p.load + m.load
    p.exec    = p.exec + m.exec
    p.total   = p.total + m.total

    if not p.loader then
      p.loader = m.loader
    elseif p.loader ~= m.loader then
      p.loader = 'mixed'
    end
  end
end

local function post_process_results(module, m)
  m.load = m.load or 0
  m.resolve = m.resolve or 0
  m.exec = m.exec or 0

  m.resolve = m.resolve / 1000000
  m.load    = m.load / 1000000
  m.exec    = m.exec / 1000000
  m.total   = m.resolve + m.load + m.exec
  m.module  = module:gsub('/', '.')
end

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

  for module, m in pairs(profile) do
    post_process_results(module, m)
    add_module_to_plugin(plugins, m)

    total_resolve = total_resolve + m.resolve
    total_load    = total_load    + m.load
    total_exec    = total_exec    + m.exec

    if #module > name_pad then
      name_pad = #module
    end

    modules[#modules+1] = m
  end

  plugins = vim.tbl_values(plugins)

  table.sort(modules, function(a, b)
    return a.total > b.total
  end)

  table.sort(plugins, function(a, b)
    return a.total > b.total
  end)

  local lines = {}
  local function add(...)
    lines[#lines+1] = string.format(...)
  end

  local l = string.rep('─', name_pad+1)
  local n = string.rep(' ', name_pad+1)

  local f1 = '%-'..name_pad..'s │ %14s │ %8.4fms │ %8.4fms │ %8.4fms │ %8.4fms │'

  local function render_table(rows, name)
    add('%s─────────────────────────────────────────────────────────────────────┐', l)
    add('%-'..name_pad..'s                                                                      │', name)
    add('%s┬────────────────┬────────────┬────────────┬────────────┬────────────┤', l)
    for _, p in ipairs(rows) do
      add(f1, p.module, p.loader, p.resolve, p.load, p.exec, p.total)
    end
    add('%s┴────────────────┴────────────┴────────────┴────────────┴────────────┘', l)
  end

  add('%s┬────────────────┬────────────┬────────────┬────────────┬────────────┐', l)
  add('%s│ Loader         │ Resolve    │ Load       │ Exec       │ Total      │', n)
  add('%s┼────────────────┼────────────┼────────────┼────────────┼────────────┤', l)
  add(f1, 'Total', '', total_resolve, total_load, total_exec, total_resolve+total_load+total_exec)
  add('%s┴────────────────┴────────────┴────────────┴────────────┴────────────┘', l)
  render_table(plugins, 'By Plugin')
  render_table(modules, 'By Module')

  local bufnr = api.nvim_create_buf(false, false)
  api.nvim_buf_set_lines(bufnr, 0, 0, false, lines)
  api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
  api.nvim_buf_set_option(bufnr, "modifiable", false)
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
    local ok, ret = pcall(orig_require, mod)

    pb.exec = uv.hrtime() - s - (pb.resolve or 0) - (pb.load or 0)

    if not ok then
      error(ret)
    end

    -- Remove the execution time for dependent modules
    if #rp > ptr then
      for i = ptr + 1, #rp do
        local dep = rp[i]
        assert(basename ~= dep)
        local pd = profile[dep]
        if pd.exec then
          pb.exec = pb.exec - pd.exec
        else
          print(string.format(
            'impatient: [error] dependency %s of %s does not have profile results. '..
            'Results will be inaccurate', dep, basename))
        end
      end
    end
    assert(pb.exec > 0)

    return ret
  end

  -- Add profiling around all the loaders
  local pl = package.loaders
  for i = 1, #pl do
    local l = pl[i]
    pl[i] = function(mod)
      local resolve_start = uv.hrtime()
      local basename = mod:gsub('%.', '/')
      local pb = profile[basename]
      if pb and not pb.loader then
        pb.loader = i == 1 and 'preloader' or '#'..i
      end
      local ok, ret = pcall(l, mod)
      if pb.resolve_end then
        pb.load = uv.hrtime() - pb.resolve_end
        pb.resolve = pb.resolve_end - resolve_start
      else
        pb.load = uv.hrtime() - resolve_start
      end
      if not ok then
        error(ret)
      end
      return l(mod)
    end
  end
end

return M
