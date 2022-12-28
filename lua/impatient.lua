local api = vim.api
local uv = vim.loop

local start = uv.hrtime()

local _loadfile = loadfile
local get_runtime = api.nvim__get_runtime
local fs_stat = uv.fs_stat
local mpack = vim.mpack

local std_cache = vim.fn.stdpath('cache')

local sep = vim.loop.os_uname().sysname:match('Windows') and '\\' or '/'

local std_dirs = {
  ['<APPDIR>']     = os.getenv('APPDIR'),
  ['<VIMRUNTIME>'] = os.getenv('VIMRUNTIME'),
  ['<STD_DATA>']   = vim.fn.stdpath('data'),
  ['<STD_CONFIG>'] = vim.fn.stdpath('config'),
}

--- @param modpath string
--- @return string
local function modpath_mangle(modpath)
  for name, dir in pairs(std_dirs) do
    modpath = modpath:gsub(dir, name)
  end
  return modpath
end

--- @param modpath string
--- @return string
local function modpath_unmangle(modpath)
  for name, dir in pairs(std_dirs) do
    modpath = modpath:gsub(name, dir)
  end
  return modpath
end

-- Overridable by user
local default_config = {
  chunks = {
    enable = true,
    path = std_cache .. sep .. 'luacache_chunks',
  },
  modpaths = {
    enable = true,
    path = std_cache.. sep .. 'luacache_modpaths',
  },
}

-- State used internally
local default_state = {
  chunks = {
    cache = {},
    dirty = false,
    get = function(self, path)
      return self.cache[modpath_mangle(path)]
    end,
    set = function(self, path, chunk)
      self.cache[modpath_mangle(path)] = chunk
    end
  },
  modpaths = {
    cache = {},
    dirty = false,
    get = function(self, mod)
      if self.cache[mod] then
        return modpath_unmangle(self.cache[mod])
      end
    end,
    set = function(self, mod, path)
      self.cache[mod] = modpath_mangle(path)
    end
  },
  log = {}
}

---@diagnostic disable-next-line: undefined-field
local M = vim.tbl_deep_extend('keep', _G.__luacache_config or {}, default_config, default_state)
_G.__luacache = M

local function log(...)
  M.log[#M.log+1] = table.concat({string.format(...)}, ' ')
end

local function print_log()
  for _, l in ipairs(M.log) do
    print(l)
  end
end

--- @param modpath string
--- @return string
local function hash(modpath)
  local stat = fs_stat(modpath)
  if stat then
    return stat.mtime.sec..stat.mtime.nsec..stat.size
  end
  error('Could not hash '..modpath)
end

local mprofile = function(_, _, _) end

--- @param basename string
--- @param paths string[]
--- @return string?, string?
local function get_runtime_file_from_parent(basename, paths)
  -- Look in the cache to see if we have already loaded a parent module.
  -- If we have then try looking in the parents directory first.
  local parents = vim.split(basename, sep)
  for i = #parents, 1, -1 do
    local parent = table.concat(vim.list_slice(parents, 1, i), sep)
    local ppath = M.modpaths:get(parent)
    if ppath then
      if (ppath:sub(-9) == (sep .. 'init.lua')) then
        ppath = ppath:sub(1, -10) -- a/b/init.lua -> a/b
      else
        ppath = ppath:sub(1, -5)  -- a/b.lua -> a/b
      end

      for _, path in ipairs(paths) do
        -- path should be of form 'a/b/c.lua' or 'a/b/c/init.lua'
        local modpath = ppath..sep..path:sub(#('lua'..sep..parent)+2)
        if fs_stat(modpath) then
          return modpath, 'cache(p)'
        end
      end
    end
  end
end

local rtp, rtpv
local RTP_PACK_PAT = '(.*)'..sep..'pack'..sep
local RTP_LUA_PAT  = '(.*)'..sep..'lua'..sep

--- @param path string
--- @return boolean
local function check_rtp(path)
  if not vim.in_fast_event() and rtpv ~= vim.o.rtp then
    rtp = {}
    for _, p in ipairs(vim.split(vim.o.rtp, ',')) do
      p = p:gsub('^~', vim.env.HOME)
      rtp[p] = true
    end
    rtpv = vim.o.rtp
  end

  path = path:match(RTP_PACK_PAT) or path:match(RTP_LUA_PAT)
  if not path then
    return false
  end

  return rtp[path] ~= nil
end

--- @param modpath string
--- @param paths string[]
--- @return boolean
local function validate_modpath(modpath, paths)
  local match = false
  for _, p in ipairs(paths) do
    if vim.endswith(modpath, p) then
      match = true
      break
    end
  end
  if not match then
    return false
  end

  if not check_rtp(modpath) then
    return false
  end

  -- On M1 this costs about 2-3ms for ~300 lookups
  return fs_stat(modpath) ~= nil
end

--- @param basename string
--- @param paths string[]
--- @return string
local function get_runtime_file_cached(basename, paths)
  local modpath, loader
  local mp = M.modpaths
  if mp.enable then
    local modpath_cached = mp:get(basename)
    if modpath_cached then
      modpath, loader = modpath_cached, 'cache'
    else
      modpath, loader = get_runtime_file_from_parent(basename, paths)
    end

    if modpath and not validate_modpath(modpath, paths) then
      modpath = nil

      -- Invalidate
      log('Invalidating module cache for module %s: not in rtp', basename)
      mp.cache[basename] = nil
      mp.dirty = true
    end
  end

  if not modpath then
    -- What Neovim does by default; slowest
    modpath, loader = get_runtime(paths, false, {is_lua=true})[1], 'standard'
  end

  if modpath then
    mprofile(basename, 'resolve_end', loader)
    if mp.enable and loader ~= 'cache' then
      log('Creating cache for module %s', basename)
      mp:set(basename, modpath)
      mp.dirty = true
    end
  end

  return modpath
end

local BASENAME_PATS = {
  -- Ordered by most specific
  'lua'.. sep ..'(.*)'..sep..'init%.lua',
  'lua'.. sep ..'(.*)%.lua'
}

--- @param pats string[]
--- @return string?
local function extract_basename(pats)
  local basename

  -- Deconstruct basename from pats
  for _, pat in ipairs(pats) do
    for i, npat in ipairs(BASENAME_PATS) do
      local m = pat:match(npat)
      if i == 2 and m and m:sub(-4) == 'init' then
        m = m:sub(0, -6)
      end
      if not basename then
        if m then
          basename = m
        end
      elseif m and m ~= basename then
        -- matches are inconsistent
        return
      end
    end
  end

  return basename
end

--- @param pats string[]
--- @param all boolean
--- @param opts {is_lua:boolean}
--- @return string[]
local function get_runtime_cached(pats, all, opts)
  local fallback = false
  if all or not opts or not opts.is_lua then
    -- Fallback
    fallback = true
  end

  --- @type string?
  local basename

  if not fallback then
    basename = extract_basename(pats)
  end

  if fallback or not basename then
    return assert(get_runtime(pats, all, opts))
  end

  return {get_runtime_file_cached(basename, pats)}
end

--- @param path string
--- @return fun()?, string?
local function load_from_cache(path)
  local mc = M.chunks

  local cache = mc:get(path)

  if not cache then
    return nil, string.format('No cache for path %s', path)
  end

  local mhash, codes = unpack(cache)

  if mhash ~= hash(path) then
    mc:set(path)
    mc.dirty = true
    return nil, string.format('Stale cache for path %s', path)
  end

  local chunk = loadstring(codes)

  if not chunk then
    mc:set(path)
    mc.dirty = true
    return nil, string.format('Cache error for path %s', path)
  end

  return chunk
end

--- @param path string
--- @return function?, string?
local function loadfile_cached(path)
  --- @type fun()?, string?
  local chunk, err

  if M.chunks.enable then
    chunk, err = load_from_cache(path)
    if chunk then
      log('Loaded cache for path %s', path)
      return chunk
    end
    log(err)
  end

  chunk, err = _loadfile(path)

  if chunk and M.chunks.enable then
    log('Creating cache for path %s', path)
    M.chunks:set(path, {hash(path), string.dump(chunk)})
    M.chunks.dirty = true
  end

  return chunk, err
end

local impatient_time

function M.enable_profile()
  local P = require('impatient.profile')
  P.setup(M, {
    std_dirs = std_dirs,
    modpath_mangle = modpath_mangle,
    impatient_time = impatient_time,
    loadfile_cached = loadfile_cached
  })
  mprofile = P.mprofile
end

local function save_cache()
  local function _save_cache(t)
    if not t.enable then
      return
    end
    if t.dirty then
      log('Updating chunk cache file: %s', t.path)
      local f = assert(io.open(t.path, 'w+b'))
      f:write(mpack.encode(t.cache))
      f:flush()
      t.dirty = false
    end
  end
  _save_cache(M.chunks)
  _save_cache(M.modpaths)
end

local function clear_cache()
  local function _clear_cache(t)
    t.cache = {}
    os.remove(t.path)
  end
  _clear_cache(M.chunks)
  _clear_cache(M.modpaths)
end

local function init_cache()
  local function _init_cache(t)
    if not t.enable then
      return
    end
    if fs_stat(t.path) then
      log('Loading cache file %s', t.path)
      local f = assert(io.open(t.path, 'rb'))
      local ok
      ok, t.cache = pcall(function()
        return mpack.decode(f:read'*a')
      end)

      if not ok then
        log('Corrupted cache file, %s. Invalidating...', t.path)
        os.remove(t.path)
        t.cache = {}
      end
      t.dirty = not ok
    end
  end

  if not uv.fs_stat(std_cache) then
    vim.fn.mkdir(std_cache, 'p')
  end

  _init_cache(M.chunks)
  _init_cache(M.modpaths)
end

local function setup()
  init_cache()

  vim.api.nvim__get_runtime = get_runtime_cached
  loadfile = loadfile_cached

  local augroup = api.nvim_create_augroup('impatient', {})

  api.nvim_create_user_command('LuaCacheClear', clear_cache, {})
  api.nvim_create_user_command('LuaCacheLog'  , print_log  , {})

  api.nvim_create_autocmd({'VimEnter', 'VimLeave'}, {
    group = augroup,
    callback = save_cache
  })

end

setup()
impatient_time = uv.hrtime() - start

return M
