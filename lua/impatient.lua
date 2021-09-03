
local M = {
  cache = {},
  profile = nil,
  dirty = false,
  path = vim.fn.stdpath('cache')..'/luacache',
  log = {}
}

_G.__luacache = M

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

local mpack = load_mpack()

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
    require('impatient.profile').print_profile(M.profile)
  end
  vim.cmd[[command LuaCacheProfile lua _G.__luacache.print_profile()]]
end

local function is_cacheable(path)
  -- Don't cache files in /tmp since they are not likely to persist.
  -- Note: Appimage versions of Neovim mount $VIMRUNTIME in /tmp in a unique
  -- directory on each launch.
  return not vim.startswith(path, '/tmp/')
end

local function hash(modpath)
  local stat = vim.loop.fs_stat(modpath)
  if stat then
    return stat.mtime.sec
  end
end

local function hrtime()
  if M.profile then
    return vim.loop.hrtime()
  end
end

local function load_package_with_cache(name)
  local resolve_start = hrtime()

  local basename = name:gsub('%.', '/')
  local paths = {"lua/"..basename..".lua", "lua/"..basename.."/init.lua"}

  for _, path in ipairs(paths) do
    local modpath = vim.api.nvim_get_runtime_file(path, false)[1]
    if modpath then
      local exec_start = hrtime()
      local chunk, err = loadfile(modpath)

      if M.profile then
        M.profile[name] = {
          resolve = exec_start - resolve_start,
          execute = hrtime() - exec_start
        }
      end

      if chunk == nil then return err end

      if is_cacheable(modpath) then
        log('Creating cache for module %s', name)
        M.cache[name] = {modpath, hash(modpath), string.dump(chunk)}
        M.dirty = true
      else
        log('Unable to cache module %s', name)
      end

      return chunk
    end
  end
  return nil
end

local reduced_rtp

-- Speed up non-cached loads by reducing the rtp path during requires
function M.update_reduced_rtp()
  local luadirs = vim.api.nvim_get_runtime_file('lua/', true)

  for i = 1, #luadirs do
    luadirs[i] = luadirs[i]:sub(1, -6)
  end

  reduced_rtp = table.concat(luadirs, ',')
end

local function load_package_with_cache_reduced_rtp(name)
  local orig_rtp = vim.api.nvim_get_option('runtimepath')
  local orig_ei  = vim.api.nvim_get_option('eventignore')

  if not reduced_rtp then
    M.update_reduced_rtp()
  end

  vim.api.nvim_set_option('eventignore', 'all')
  vim.api.nvim_set_option('rtp', reduced_rtp)

  local found = load_package_with_cache(name)

  vim.api.nvim_set_option('rtp', orig_rtp)
  vim.api.nvim_set_option('eventignore', orig_ei)

  return found
end

local function load_from_cache(name)
  local resolve_start = hrtime()
  if M.cache[name] == nil then
    log('No cache for module %s', name)
    return 'No cache entry'
  end

  local modpath, mhash, codes = unpack(M.cache[name])

  if mhash ~= hash(modpath) then
    log('Stale cache for module %s', name)
    M.cache[name] = nil
    M.dirty = true
    return 'Stale cache'
  end

  local exec_start = hrtime()
  local chunk = loadstring(codes)

  if M.profile then
    M.profile[name] = {
      resolve = exec_start - resolve_start,
      execute = hrtime() - exec_start
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
    io.open(M.path, 'wb'):write(mpack.pack(M.cache))
    M.dirty = false
  end
end

function M.clear_cache()
  M.cache = {}
  os.remove(M.path)
end

local function setup()
  if vim.loop.fs_stat(M.path) then
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

  -- Fix the position of the preloader. This also makes loading modules like 'ffi'
  -- and 'bit' quicker
  if package.loaders[1] == vim._load_package then
    -- Move vim._load_package to the second position
    local vim_load = table.remove(package.loaders, 1)
    table.insert(package.loaders, 2, vim_load)
  end

  table.insert(package.loaders, 2, load_from_cache)
  table.insert(package.loaders, 3, load_package_with_cache_reduced_rtp)
  table.insert(package.loaders, 4, load_package_with_cache)

  vim.cmd[[
    augroup impatient
      autocmd VimEnter,VimLeave * lua _G.__luacache.save_cache()
      autocmd OptionSet runtimepath lua _G.__luacache.update_reduced_rtp(true)
    augroup END

    command LuaCacheClear lua _G.__luacache.clear_cache()
    command LuaCacheLog   lua _G.__luacache.print_log()
  ]]

end

setup()

return M
