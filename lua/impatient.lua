local vim = vim
local api = vim.api
local uv = vim.loop

local get_option = api.nvim_get_option
local get_runtime_file = api.nvim_get_runtime_file
local globpath = vim.fn.globpath
local fs_stat = uv.fs_stat

local impatient_start = uv.hrtime()
local impatient_dur

local M = {
  cache = {},
  profile = nil,
  dirty = false,
  path = vim.fn.stdpath('cache')..'/luacache',
  log = {}
}

if _G.use_cachepack == nil then
  _G.use_cachepack = not (vim.mpack and vim.mpack.encode)
end

_G.__luacache = M

local mpack = _G.use_cachepack and require('impatient.cachepack') or vim.mpack

local function log(...)
  M.log[#M.log+1] = table.concat({string.format(...)}, ' ')
end

function M.print_log()
  for _, l in ipairs(M.log) do
    print(l)
  end
end

function M.enable_profile()
  local ip = require('impatient.profile')

  M.profile = {}
  ip.mod_require(M.profile)

  M.mark_resolve = function(mod, loader)
    local mp = M.profile[mod]
    mp.resolve_end = uv.hrtime()
    mp.loader  = loader
  end

  M.print_profile = function()
    M.profile['impatient'] = {
      exec   = impatient_dur,
      loader = 'standard'
    }
    ip.print_profile(M.profile)
  end

  vim.cmd[[command! LuaCacheProfile lua _G.__luacache.print_profile()]]
end

local function hash(modpath)
  local stat = fs_stat(modpath)
  if stat then
    return stat.mtime.sec
  end
end

local appdir = os.getenv('APPDIR')

local function modpath_mangle(modpath)
  if appdir then
    modpath = modpath:gsub(appdir, '/$APPDIR')
  end
  return modpath
end

local function modpath_unmangle(modpath)
  if appdir then
    modpath = modpath:gsub('/$APPDIR', appdir)
  end
  return modpath
end

local reduced_rtp
local rtp

local function update_reduced_rtp()
  local cur_rtp = get_option('runtimepath')

  if cur_rtp ~= rtp then
    log('Updating reduced rtp')
    rtp = cur_rtp
    local luadirs = get_runtime_file('lua/', true)

    for i = 1, #luadirs do
      luadirs[i] = luadirs[i]:sub(1, -6)
    end
    reduced_rtp = table.concat(luadirs, ',')
  end
end

local function get_lua_runtime_file(basename, path)
  -- Look in the cache to see if we have already loaded the parent module.
  -- If we have then try looking in the parents dir first.
  local parents = vim.split(basename, '/')
  for i = #parents, 1, -1 do
    local parent = table.concat(vim.list_slice(parents, 1, i), '/')
    if M.cache[parent] then
      local ppath = M.cache[parent][1]
      if ppath:sub(-9) == '/init.lua' then
        ppath = ppath:sub(1, -10) -- a/b/init.lua -> a/b
      else
        ppath = ppath:sub(1, -5)  -- a/b.lua -> a/b
      end

      -- path should be of form 'a/b/c.lua' or 'a/b/c/init.lua'
      local modpath = ppath..'/'..path:sub(#('lua/'..parent)+2)
      if fs_stat(modpath) then
        return modpath, true
      end
    end
  end

  if reduced_rtp then
    return globpath(reduced_rtp, path, true, true)[1]
  end

  -- What Neovim does by default; slowest
  return get_runtime_file(path, false)[1]
end

local function load_package_with_cache(name)
  if not vim.in_fast_event() then
    update_reduced_rtp()
  end

  local basename = name:gsub('%.', '/')
  local paths = {"lua/"..basename..".lua", "lua/"..basename.."/init.lua"}

  for _, path in ipairs(paths) do
    local modpath, cache_success  = get_lua_runtime_file(basename, path)
    if modpath then
      if M.mark_resolve then
        local loader = cache_success and 'cached resolve'  or
                       reduced_rtp   and 'reduced'         or 'standard'
        M.mark_resolve(basename, loader)
      end

      local chunk, err = loadfile(modpath)
      if chunk == nil then
        error(err)
      end

      log('Creating cache for module %s', basename)
      M.cache[basename] = {modpath_mangle(modpath), hash(modpath), string.dump(chunk)}
      M.dirty = true

      return chunk
    end
  end

  -- Copied from neovim/src/nvim/lua/vim.lua
  for _, trail in ipairs(vim._so_trails) do
    local path = "lua"..trail:gsub('?', basename) -- so_trails contains a leading slash
    local found
    if reduced_rtp then
      found = globpath(reduced_rtp, path, true, true)[1]
    else
      found = get_runtime_file(path, false)[1]
    end
    if found then
      if M.mark_resolve then
        local loader = reduced_rtp and 'reduced' or 'standard'
        M.mark_resolve(basename, loader..'(so)')
      end

      -- Making function name in Lua 5.1 (see src/loadlib.c:mkfuncname) is
      -- a) strip prefix up to and including the first dash, if any
      -- b) replace all dots by underscores
      -- c) prepend "luaopen_"
      -- So "foo-bar.baz" should result in "luaopen_bar_baz"
      local dash = name:find("-", 1, true)
      local modname = dash and name:sub(dash + 1) or name
      local f, err = package.loadlib(found, "luaopen_"..modname:gsub("%.", "_"))
      return f or error(err)
    end
  end

  return nil
end

local function load_from_cache(name)
  local basename = name:gsub('%.', '/')

  if M.cache[basename] == nil then
    log('No cache for module %s', basename)
    return 'No cache entry'
  end

  local modpath, mhash, codes = unpack(M.cache[basename])

  if mhash ~= hash(modpath_unmangle(modpath)) then
    log('Stale cache for module %s', basename)
    M.cache[basename] = nil
    M.dirty = true
    return 'Stale cache'
  end

  if M.mark_resolve then
    M.mark_resolve(basename, 'cache')
  end

  local chunk = loadstring(codes)

  if not chunk then
    M.cache[basename] = nil
    M.dirty = true
    log('Error loading cache for module. Invalidating', basename)
    return 'Cache error'
  end

  return chunk
end

function M.save_cache()
  if M.dirty then
    log('Updating cache file: %s', M.path)
    local f = io.open(M.path, 'w+b')
    f:write(mpack.encode(M.cache))
    f:flush()
    M.dirty = false
  end
end

function M.clear_cache()
  M.cache = {}
  os.remove(M.path)
end

-- -- run a crude hash on vim._load_package to make sure it hasn't changed.
-- local function verify_vim_loader()
--   local expected_sig = 31172

--   local dump = {string.byte(string.dump(vim._load_package), 1, -1)}
--   local actual_sig = #dump
--   for i = 1, #dump do
--     actual_sig = actual_sig + dump[i]
--   end

--   if actual_sig ~= expected_sig then
--     print(string.format('warning: vim._load_package has an unexpected value, impatient might not behave properly (%d)', actual_sig))
--   end
-- end

local function setup()
  if uv.fs_stat(M.path) then
    log('Loading cache file %s', M.path)
    local f = io.open(M.path, 'rb')
    local ok
    ok, M.cache = pcall(function()
      return mpack.decode(f:read'*a')
    end)

    if not ok then
      log('Corrupted cache file, %s. Invalidating...', M.path)
      os.remove(M.path)
      M.cache = {}
    end
    M.dirty = not ok
  end

  local insert = table.insert
  local package = package

  -- verify_vim_loader()

  -- Fix the position of the preloader. This also makes loading modules like 'ffi'
  -- and 'bit' quicker
  if package.loaders[1] == vim._load_package then
    -- Remove vim._load_package and replace with our version
    table.remove(package.loaders, 1)
  end

  insert(package.loaders, 2, load_from_cache)
  insert(package.loaders, 3, load_package_with_cache)

  vim.cmd[[
    augroup impatient
      autocmd VimEnter,VimLeave * lua _G.__luacache.save_cache()
    augroup END

    command! LuaCacheClear lua _G.__luacache.clear_cache()
    command! LuaCacheLog   lua _G.__luacache.print_log()
  ]]

end

setup()

impatient_dur = uv.hrtime() - impatient_start

return M
