local M = {}
local C

local sep = vim.loop.os_uname().sysname:match('Windows') and '\\' or '/'

local api, uv = vim.api, vim.loop

--- @param title string
--- @param lines string[]
local function open_buffer(title, lines)
  local bufnr = api.nvim_create_buf(false, false)
  api.nvim_buf_set_lines(bufnr, 0, 0, false, lines)
  vim.bo[bufnr].bufhidden = 'wipe'
  vim.bo[bufnr].buftype = 'nofile'
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false
  api.nvim_buf_set_name(bufnr, title)
  api.nvim_set_current_buf(bufnr)
end

--- @param x number
local function time_tostr(x)
  if x == 0 then
    return '?'
  end
  return (string.format('%8.3fms', x / 1000000))
end

--- @param x integer
local function mem_tostr(x)
  local unit = ''
  for _, u in ipairs{'K', 'M', 'G'} do
    if x < 1000 then
      break
    end
    x = x / 1000
    unit = u
  end
  return string.format('%1.1f%s', x, unit)
end

--- @param x number
local function pct_to_str(x)
  return string.format('%3.1f%%', x * 100)
end

--- @param std_dirs {[string]: string}
--- @param impatient_time integer
local function print_profile(I, std_dirs, impatient_time)
  local mod_profile = I.modpaths.profile
  local chunk_profile = I.chunks.profile

  if not mod_profile and not chunk_profile then
    print('Error: profiling was not enabled')
    return
  end

  local total_resolve = 0
  local total_load = 0
  local modules = {}

  for path, m in pairs(chunk_profile) do
    m.load = m.load_end - m.load_start
    m.load = m.load
    m.path = path or '?'
  end

  local module_content_width = 0

  local unloaded = {}

  local count = 0
  local load_cached_count = 0
  local resolve_cached_count = 0

  for module, m in pairs(mod_profile) do
    local module_dot = module:gsub(sep, '.')
    m.module = module_dot

    if not package.loaded[module_dot] and not package.loaded[module] then
      unloaded[#unloaded+1] = m
    else
      m.resolve = 0
      if m.resolve_start and m.resolve_end then
        m.resolve = m.resolve_end - m.resolve_start
        m.resolve = m.resolve
      end

      m.loader = m.loader or m.loader_guess

      local path = I.modpaths.cache[module]
      local path_prof = chunk_profile[path]
      m.path = path or '?'

      if path_prof then
        chunk_profile[path] = nil
        m.load = path_prof.load
        m.ploader = path_prof.loader
      else
        m.load = 0
        m.ploader = 'NA'
      end

      count = count + 1
      if vim.startswith(m.loader, 'cache') then
        resolve_cached_count = resolve_cached_count + 1
      end

      if vim.startswith(m.ploader, 'cache') then
        load_cached_count = load_cached_count + 1
      end

      total_resolve = total_resolve + m.resolve
      total_load = total_load + m.load

      if #module > module_content_width then
        module_content_width = #module
      end

      modules[#modules+1] = m
    end
  end

  table.sort(modules, function(a, b)
    return (a.resolve + a.load) > (b.resolve + b.load)
  end)

  local paths = {}

  local path_cached_count = 0
  local total_paths_load = 0
  for _, m in pairs(chunk_profile) do
    paths[#paths+1] = m
    if vim.startswith(m.loader, 'cache') then
      path_cached_count = path_cached_count + 1
    end
    total_paths_load = total_paths_load + m.load
  end

  table.sort(paths, function(a, b)
    return a.load > b.load
  end)

  local lines = {}
  --- @param fmt string
  local function add(fmt, ...)
    local args = {...}
    for i, a in ipairs(args) do
      if type(a) == 'number' then
        args[i] = time_tostr(a)
      end
    end

    lines[#lines+1] = string.format(fmt, unpack(args))
  end

  local time_cell_width = 12
  local loader_cell_width = 11
  local time_content_width = time_cell_width - 2
  local loader_content_width = loader_cell_width - 2
  local module_cell_width = module_content_width + 2

  local tcwl = string.rep('─', time_cell_width)
  local lcwl = string.rep('─', loader_cell_width)
  local mcwl = string.rep('─', module_cell_width+2)

  local n = string.rep('─', 200)

  local module_cell_format = '%-'..module_cell_width..'s'
  local loader_format = '%-'..loader_content_width..'s'
  local line_format = '%s │ %s │ %s │ %s │ %s │ %s'

  local row_fmt = line_format:format(
    ' %'..time_content_width..'s',
    loader_format,
    '%'..time_content_width..'s',
    loader_format,
    module_cell_format,
    '%s')

  local title_fmt = line_format:format(
    ' %-'..time_content_width..'s',
    loader_format,
    '%-'..time_content_width..'s',
    loader_format,
    module_cell_format,
    '%s')

  local title1_width = time_cell_width+loader_cell_width-1
  local title1_fmt = ('%s │ %s │'):format(
    ' %-'..title1_width..'s', '%-'..title1_width..'s')

  add('Note: this report is not a measure of startup time. Only use this for comparing')
  add('between cached and uncached loads of Lua modules')
  add('')

  add('Cache files:')
  for _, f in ipairs{ I.chunks.path, I.modpaths.path } do
    local size = vim.loop.fs_stat(f).size
    add('  %s %s', f, mem_tostr(size))
  end
  add('')

  add('Standard directories:')
  for alias, path in pairs(std_dirs) do
    add('  %-12s -> %s', alias, path)
  end
  add('')

  local total = total_paths_load + impatient_time + total_load + total_resolve
  local resolve_pct = pct_to_str(resolve_cached_count / count)
  local load_pct = pct_to_str(load_cached_count / count)
  local path_pct = pct_to_str(path_cached_count / #paths)

  add('─────────────────────────────────────────────────────┐')
  add('Summary                                              │')
  add('────────────────────────┬────────────────────────────┤')
  add('Impatient overhead      │ %s                 │', impatient_time)
  add('Total resolve (modules) │ %s (%6s cached) │', total_resolve, resolve_pct)
  add('Total load (modules)    │ %s (%6s cached) │', total_load, load_pct)
  add('Total load (paths)      │ %s (%6s cached) │', total_paths_load, path_pct)
  add('────────────────────────┼────────────────────────────┤')
  add('Total                   │ %s                 │', total)
  add('────────────────────────┴────────────────────────────┘')
  add('')

  add('%s─%s┬%s─%s┐', tcwl, lcwl, tcwl, lcwl)
  add(title1_fmt, 'Resolve', 'Load')
  add('%s┬%s┼%s┬%s┼%s┬%s', tcwl, lcwl, tcwl, lcwl, mcwl, n)
  add(title_fmt, 'Time', 'Method', 'Time', 'Method', 'Module', 'Path')
  add('%s┼%s┼%s┼%s┼%s┼%s', tcwl, lcwl, tcwl, lcwl, mcwl, n)
  add(row_fmt, total_resolve, '', total_load, '', 'Total', '')
  add('%s┼%s┼%s┼%s┼%s┼%s', tcwl, lcwl, tcwl, lcwl, mcwl, n)
  for _, p in ipairs(modules) do
    add(row_fmt, p.resolve, p.loader, p.load, p.ploader, p.module, p.path)
  end
  add('%s┴%s┴%s┴%s┴%s┴%s', tcwl, lcwl, tcwl, lcwl, mcwl, n)

  if #paths > 0 then
    add('')
    add(n)
    local f3 = ' %'..time_content_width..'s │ %'..loader_content_width..'s │ %s'
    add('Files loaded with no associated module')
    add('%s┬%s┬%s', tcwl, lcwl, n)
    add(f3, 'Time', 'Loader', 'Path')
    add('%s┼%s┼%s', tcwl, lcwl, n)
    add(f3, total_paths_load, '', 'Total')
    add('%s┼%s┼%s', tcwl, lcwl, n)
    for _, p in ipairs(paths) do
      add(f3, p.load, p.loader, p.path)
    end
    add('%s┴%s┴%s', tcwl, lcwl, n)
  end

  if #unloaded > 0 then
    add('')
    add(n)
    add('Modules which were unable to loaded')
    add(n)
    for _, p in ipairs(unloaded) do
      lines[#lines+1] = p.module
    end
    add(n)
  end

  open_buffer('Impatient Profile Report', lines)
end

--- @alias LoadfileFn fun(path: string): fun()

--- @param loadfile_cached LoadfileFn
local function add_profiling(loadfile_cached)
  local orig_loadlib = package.loadlib
  package.loadlib = function(path, fun)
    M.cprofile(path, 'load_start')
    local f, err = orig_loadlib(path, fun)
    M.cprofile(path, 'load_end', 'standard')
    return f, err
  end

  local orig_loadfile = loadfile
  loadfile = function(path)
    M.cprofile(path, 'load_start')
    local chunk, err = orig_loadfile(path)
    local loader = orig_loadfile == loadfile_cached and 'cache' or 'standard'
    M.cprofile(path, 'load_end', loader)
    return chunk, err
  end

  local mprofile = C.modpaths.profile

  local orig_require = require
  require = function(mod)
    local basename = mod:gsub('%.', sep)
    if not mprofile[basename] then
      mprofile[basename] = {}
      mprofile[basename].resolve_start = uv.hrtime()
      mprofile[basename].loader_guess = ''
    end
    return orig_require(mod)
  end

  -- Keep track of which loader was used
  local pl = package.loaders
  for i = 1, #pl do
    local l = pl[i]
    --- @param mod string
    pl[i] = function(mod)
      local basename = mod:gsub('%.', sep)
      if mprofile[basename] then
        mprofile[basename].loader_guess = i == 1 and 'preloader' or 'loader #'..i
      end
      return l(mod)
    end
  end
end

M.setup = function(_C, m)
  C = _C
  C.chunks.profile = {}
  C.modpaths.profile = {}
  M.modpath_mangle = m.modpath_mangle

  api.nvim_create_user_command('LuaCacheProfile', function()
    print_profile(C, m.std_dirs, m.impatient_time)
  end, {})

  add_profiling(m.loadfile_cached)
end

--- @param entry string
--- @param event string
--- @param loader? string
local function profile(m, entry, event, loader)
  local mp = m.profile

  if not mp then
    return
  end

  mp[entry] = mp[entry] or {}

  if not mp[entry].loader then
    mp[entry].loader = loader
  end

  if not mp[entry][event] then
    mp[entry][event] = uv.hrtime()
  end
end

--- @param mod string
--- @param event string
--- @param loader? string
function M.mprofile(mod, event, loader)
  profile(C.modpaths, mod, event, loader)
end

--- @param path string
--- @param event string
--- @param loader? string
function M.cprofile(path, event, loader)
  if C.chunks.profile then
    path = M.modpath_mangle(path)
  end
  profile(C.chunks, path, event, loader)
end

return M
