-- Fix the position of the preloader. This also makes loading modules like 'ffi'
-- and 'bit' quicker
if package.loaders[1] == vim._load_package then
    -- Move vim._load_package to the second position
    local preload = table.remove(package.loaders, 1)
    table.insert(package.loaders, 2, preload)
end

do
  -- Speed up non-cached loads by reducing the rtp path during requires
  local luadirs = vim.api.nvim_get_runtime_file('lua/', true)

  for i = 1, #luadirs do
    luadirs[i] = luadirs[i]:sub(1, -6)
  end

  local luartp = table.concat(luadirs, ',')

  local function load_package(name)
    local orig_rtp = vim.o.rtp
    vim.api.nvim_set_option('rtp', luartp)
    local found = vim._load_package(name)
    vim.api.nvim_set_option('rtp', orig_rtp)
    return found
  end

  table.insert(package.loaders, 2, load_package)
end

do
  local M = {
    cache = {},
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
    M.log[#M.log+1] = table.concat({...}, ' ')
  end

  function M.print_log()
    for _, l in ipairs(M.log) do
      print(l)
    end
  end

  local function hash(modpath)
    return vim.loop.fs_stat(modpath).mtime.sec
  end

  local function load_package_with_cache(name)
    local basename = name:gsub('%.', '/')
    local paths = {"lua/"..basename..".lua", "lua/"..basename.."/init.lua"}
    for _, path in ipairs(paths) do
      local found = vim.api.nvim_get_runtime_file(path, false)
      if #found > 0 then
        local f, err = loadfile(found[1])

        local modpath = found[1]
        M.cache[name] = {modpath, hash(modpath), string.dump(f)}
        log('Creating cache for module', name)
        M.dirty = true

        return f or error(err)
      end
    end
    return nil
  end

  table.insert(package.loaders, 2, load_package_with_cache)

  function preloader(name)
    if M.cache[name] == nil then
      -- Not sure this branch is reachable
      return
    end
    local f, _, codes = unpack(M.cache[name])

    return loadstring(codes)()
  end

  local function setup()
    if vim.loop.fs_stat(M.path) then
      log('Loading cache file', M.path)
      local f = io.open(M.path, 'rb')
      M.cache = mpack.unpack(f:read'*a')
      M.dirty = false

      for mod, v in pairs(M.cache) do
        local f, fhash = v[1], v[2]
        if fhash ~= hash(f) then
          log('Stale cache for module', mod)
          M.cache[mod] = nil
        elseif package.loaded[mod] == nil then
          package.preload[mod] = preloader
        end
      end
    end

    function M.enter()
      if M.dirty then
        log('Updating cache file:', M.path)
        io.open(M.path, 'wb'):write(mpack.pack(M.cache))
        M.dirty = false
      end
    end

    vim.cmd [[autocmd VimEnter,VimLeave * lua _G.__luacache.enter()]]

    vim.cmd [[command LuaCacheClear lua os.remove(_G.__luacache.path)]]
    vim.cmd [[command LuaCacheLog   lua _G.__luacache.print_log()]]
  end

  setup()
end
