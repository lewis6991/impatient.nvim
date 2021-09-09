local vim = vim
local api = vim.api
local uv = vim.loop

local get_option, set_option = api.nvim_get_option, api.nvim_set_option
local get_runtime_file = api.nvim_get_runtime_file

local impatient_start = uv.hrtime()
local impatient_dur

local M = {
  cache = {},
  profile = nil,
  dirty = false,
  path = vim.fn.stdpath('cache')..'/luacache',
  log = {}
}

_G.use_cachepack = _G.use_cachepack ~= false

_G.__luacache = M

local ffi = require('ffi')

-- using double for packing/unpacking numbers has no conversion overhead
local sizeof_c_double = ffi.sizeof("double")
local c_double = ffi.typeof("double[1]")

local CachePack = {}

function CachePack.pack(cache)
  local buf = {}

  local function write_number(num)
    buf[#buf+1] = ffi.string(c_double(num), sizeof_c_double)
  end

  local function write_string(str)
    write_number(#str)
    buf[#buf+1] = str
  end

  local total_keys = vim.tbl_count(cache)

  write_number(total_keys)
  for k,v in pairs(cache) do
    write_string(k)
    write_string(v[1] or "")
    write_number(v[2] or 0)
    write_string(v[3] or "")
  end

  return table.concat(buf)
end

function CachePack.unpack(str)
  if str == nil or #str == 0 then
    return {}
  end

  local buf = ffi.new("const char[?]", #str, str)
  local buf_pos = 0

  local function read_number()
    if (buf_pos > #str) then
      error("buffer access violation")
    end
    local res = ffi.cast("double*", buf + buf_pos)[0]
    buf_pos = buf_pos + sizeof_c_double
    return res
  end

  local function read_string()
    local len = read_number()
    local res = ffi.string(buf + buf_pos, len)
    buf_pos = buf_pos + len
    return res
  end

  local cache = {}

  local total_keys = read_number()
  for _ = 1, total_keys do
    local k = read_string()
    cache[k] = {
      read_string(),
      read_number(),
      read_string()
    }
  end

  return cache
end

local function load_mpack()
  local has_builtin_mpack, mpack_mod = pcall(require, 'mpack')

  if has_builtin_mpack then
    return mpack_mod
  end

  local has_packer, packer_luarocks = pcall(require, 'packer.luarocks')
  if has_packer then
    packer_luarocks.setup_paths()
  end

  return require('mpack')
end

local mpack = _G.use_cachepack and CachePack or load_mpack()

local function log(...)
  M.log[#M.log+1] = table.concat({string.format(...)}, ' ')
end

function M.print_log()
  for _, l in ipairs(M.log) do
    print(l)
  end
end

function M.enable_profile()
  M.profile = {}
  M.print_profile = function()
    M.profile['impatient'] = {
      resolve = 0,
      load    = impatient_dur,
      loader  = 'standard'
    }
    require('impatient.profile').print_profile(M.profile)
  end
  vim.cmd[[command! LuaCacheProfile lua _G.__luacache.print_profile()]]
end

local function hash(modpath)
  local stat = uv.fs_stat(modpath)
  if stat then
    return stat.mtime.sec
  end
end

local function hrtime()
  if M.profile then
    return uv.hrtime()
  end
end

local function modpath_pack(modpath)
      local appdir = os.getenv('APPDIR')
      if appdir ~= nil then
        modpath = modpath:gsub(appdir, '/appimage')
      end
      return modpath
end

local function modpath_unpack(modpath)
      local appdir = os.getenv('APPDIR')
      if appdir ~= nil then
        modpath = modpath:gsub('/appimage', appdir)
      end
      return modpath
end


local function load_package_with_cache(name, loader)
  local resolve_start = hrtime()

  local basename = name:gsub('%.', '/')
  local paths = {"lua/"..basename..".lua", "lua/"..basename.."/init.lua"}

  for _, path in ipairs(paths) do
    local modpath = get_runtime_file(path, false)[1]
    if modpath then
      local load_start = hrtime()
      local chunk, err = loadfile(modpath)

      if M.profile then
        M.profile[name] = {
          resolve = load_start - resolve_start,
          load    = hrtime() - load_start,
          loader  = loader or 'standard'
        }
      end

      if chunk == nil then return err end

      log('Creating cache for module %s', name)
      M.cache[name] = {modpath_pack(modpath), hash(modpath), string.dump(chunk)}
      M.dirty = true

      return chunk
    end
  end
  return nil
end

local reduced_rtp

-- Speed up non-cached loads by reducing the rtp path during requires
function M.update_reduced_rtp()
  local luadirs = get_runtime_file('lua/', true)

  for i = 1, #luadirs do
    luadirs[i] = luadirs[i]:sub(1, -6)
  end

  reduced_rtp = table.concat(luadirs, ',')
end

local function load_package_with_cache_reduced_rtp(name)
  local orig_rtp = get_option('runtimepath')
  local orig_ei  = get_option('eventignore')

  if not reduced_rtp then
    M.update_reduced_rtp()
  end

  set_option('eventignore', 'all')
  set_option('rtp', reduced_rtp)

  local found = load_package_with_cache(name, 'reduced')

  set_option('rtp', orig_rtp)
  set_option('eventignore', orig_ei)

  return found
end

local function load_from_cache(name)
  local resolve_start = hrtime()
  if M.cache[name] == nil then
    log('No cache for module %s', name)
    return 'No cache entry'
  end

  local modpath, mhash, codes = unpack(M.cache[name])

  if mhash ~= hash(modpath_unpack(modpath)) then
    log('Stale cache for module %s', name)
    M.cache[name] = nil
    M.dirty = true
    return 'Stale cache'
  end

  local load_start = hrtime()
  local chunk = loadstring(codes)

  if M.profile then
    M.profile[name] = {
      resolve = load_start - resolve_start,
      load    = hrtime() - load_start,
      loader  = 'cache'
    }
  end

  if not chunk then
    M.cache[name] = nil
    M.dirty = true
    log('Error loading cache for module. Invalidating', name)
    return 'Cache error'
  end

  return chunk
end

function M.save_cache()
  if M.dirty then
    log('Updating cache file: %s', M.path)
    local f = io.open(M.path, 'w+b')
    f:write(mpack.pack(M.cache))
    f:flush()
    M.dirty = false
  end
end

function M.clear_cache()
  M.cache = {}
  os.remove(M.path)
end

local function setup()
  if uv.fs_stat(M.path) then
    log('Loading cache file %s', M.path)
    local f = io.open(M.path, 'rb')
    local ok
    ok, M.cache = pcall(function()
      return mpack.unpack(f:read'*a')
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

  -- Fix the position of the preloader. This also makes loading modules like 'ffi'
  -- and 'bit' quicker
  if package.loaders[1] == vim._load_package then
    -- Move vim._load_package to the second position
    local vim_load = table.remove(package.loaders, 1)
    insert(package.loaders, 2, vim_load)
  end

  insert(package.loaders, 2, load_from_cache)
  insert(package.loaders, 3, load_package_with_cache_reduced_rtp)
  insert(package.loaders, 4, load_package_with_cache)

  vim.cmd[[
    augroup impatient
      autocmd VimEnter,VimLeave * lua _G.__luacache.save_cache()
      autocmd OptionSet runtimepath lua _G.__luacache.update_reduced_rtp(true)
    augroup END

    command! LuaCacheClear lua _G.__luacache.clear_cache()
    command! LuaCacheLog   lua _G.__luacache.print_log()
  ]]

end

setup()

impatient_dur = uv.hrtime() - impatient_start

return M
