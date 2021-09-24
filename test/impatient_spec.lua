local helpers = require('test.functional.helpers')()

local clear    = helpers.clear
local exec_lua = helpers.exec_lua
local eq       = helpers.eq
local cmd      = helpers.command

local gen_exp = function(use_cachepack)
  local nvim05 = exec_lua('return vim.version().minor') == 5
  local exp = {
    'No cache for module plugins',
    'Updating reduced rtp',
    'Creating cache for module plugins',
    'No cache for module telescope',
    'Updating reduced rtp',
    'Creating cache for module telescope',
    'No cache for module telescope/_extensions',
    'Creating cache for module telescope/_extensions',
    'No cache for module gitsigns',
    'Creating cache for module gitsigns',
    'No cache for module plenary/async/async',
    'Creating cache for module plenary/async/async',
    'No cache for module plenary/vararg',
    'Creating cache for module plenary/vararg',
    'No cache for module plenary/vararg/rotate',
    'Creating cache for module plenary/vararg/rotate',
    'No cache for module plenary/tbl',
    'Creating cache for module plenary/tbl',
    'No cache for module plenary/errors',
    'Creating cache for module plenary/errors',
    'No cache for module plenary/functional',
    'Creating cache for module plenary/functional',
    'No cache for module plenary/async/util',
    'Creating cache for module plenary/async/util',
    'No cache for module plenary/async/control',
    'Creating cache for module plenary/async/control',
    'No cache for module plenary/async/structs',
    'Creating cache for module plenary/async/structs',
    'No cache for module gitsigns/status',
    'Creating cache for module gitsigns/status',
    'No cache for module gitsigns/git',
    'Creating cache for module gitsigns/git',
    'No cache for module plenary/job',
    'Creating cache for module plenary/job',
    'No cache for module gitsigns/debug',
    'Creating cache for module gitsigns/debug',
    'No cache for module gitsigns/util',
    'Creating cache for module gitsigns/util',
    'No cache for module gitsigns/hunks',
    'Creating cache for module gitsigns/hunks',
    'No cache for module gitsigns/signs',
    'Creating cache for module gitsigns/signs',
    'No cache for module gitsigns/config',
    'Creating cache for module gitsigns/config',
    'No cache for module gitsigns/manager',
    'Creating cache for module gitsigns/manager',
    'No cache for module gitsigns/cache',
    'Creating cache for module gitsigns/cache',
    'No cache for module gitsigns/debounce',
    'Creating cache for module gitsigns/debounce',
    'No cache for module gitsigns/highlight',
    'Creating cache for module gitsigns/highlight',
    'No cache for module spellsitter',
    'Creating cache for module spellsitter',
    'No cache for module vim/treesitter/query',
    'Creating cache for module vim/treesitter/query',
    'No cache for module vim/treesitter/language',
    'Creating cache for module vim/treesitter/language',
    'No cache for module vim/treesitter',
    'Creating cache for module vim/treesitter',
    'No cache for module vim/treesitter/languagetree',
    'Creating cache for module vim/treesitter/languagetree',
    'No cache for module colorizer',
    'Creating cache for module colorizer',
    'No cache for module colorizer/nvim',
    'Creating cache for module colorizer/nvim',
    'No cache for module colorizer/trie',
    'Creating cache for module colorizer/trie',
    'No cache for module lspconfig',
    'Creating cache for module lspconfig',
    'No cache for module lspconfig/configs',
    'Creating cache for module lspconfig/configs',
    'No cache for module lspconfig/util',
    'Creating cache for module lspconfig/util',
    use_cachepack and 'No cache for module vim/uri' or nil,
    use_cachepack and 'Creating cache for module vim/uri' or nil,
    'No cache for module vim/lsp',
    'Creating cache for module vim/lsp',
    nvim05 and 'No cache for module vim/F' or nil,
    nvim05 and 'Creating cache for module vim/F' or nil,
    'No cache for module vim/lsp/handlers',
    'Creating cache for module vim/lsp/handlers',
    'No cache for module vim/lsp/log',
    'Creating cache for module vim/lsp/log',
    'No cache for module vim/lsp/protocol',
    'Creating cache for module vim/lsp/protocol',
    'No cache for module vim/lsp/util',
    'Creating cache for module vim/lsp/util',
    'No cache for module vim/highlight',
    'Creating cache for module vim/highlight',
    'No cache for module vim/lsp/buf',
    'Creating cache for module vim/lsp/buf',
    'No cache for module vim/lsp/rpc',
    'Creating cache for module vim/lsp/rpc',
    'No cache for module vim/lsp/diagnostic',
    'Creating cache for module vim/lsp/diagnostic',
    'No cache for module vim/lsp/codelens',
    'Creating cache for module vim/lsp/codelens',
    'No cache for module bufferline',
    'Creating cache for module bufferline',
    'No cache for module bufferline/constants',
    'Creating cache for module bufferline/constants',
    'No cache for module bufferline/utils',
    'Creating cache for module bufferline/utils',
    'Updating cache file: scratch/cache/nvim/luacache'
  }

  -- Realign table
  local exp1 = {}
  for _, v in pairs(exp) do
    exp1[#exp1+1] = v
  end

  return exp1
end

describe('impatient', function()
  local function reset()
    clear()
    cmd [[set runtimepath=$VIMRUNTIME,.,./test]]
    cmd [[let $XDG_CACHE_HOME='scratch/cache']]
    cmd [[set packpath=]]
  end

  before_each(function()
    reset()
  end)

  it('load plugins without impatient', function()
    exec_lua([[require('plugins')]])
  end)

  local function tests(use_cachepack)
    local function run()
      exec_lua([[
        _G.use_cachepack = ...
        require('impatient')
        require('plugins')
        _G.__luacache.save_cache()
      ]], use_cachepack)
    end

    it('creates cache', function()
      os.execute[[rm -rf scratch/cache]]
      run()
      eq(gen_exp(use_cachepack), exec_lua("return _G.__luacache.log"))
    end)

    it('loads cache', function()
      run()

      eq({ 'Loading cache file scratch/cache/nvim/luacache' },
        exec_lua("return _G.__luacache.log"))

      assert(use_cachepack == exec_lua("return _G.package.loaded['impatient.cachepack'] ~= nil"))
    end)
  end

  describe('using mpack', function()
    tests(false)
  end)

  describe('using cachepack', function()
    tests(true)
  end)

  it('shouldn\'t be slow when loading missing modules', function()
    os.execute[[rm -rf scratch/cache]]

    local total_vim_load_dur = 0
    local total_imp_load_dur = 0

    local function load_no_exist_mod()
      return exec_lua[[
        local a = vim.loop.hrtime()
        pcall(require, 'does.not.exist')
        return (vim.loop.hrtime() - a)/1e6
      ]]
    end

    for _ = 1, 20 do
      reset()
      local vim_load_dur = load_no_exist_mod()
      total_vim_load_dur = total_vim_load_dur + vim_load_dur
      exec_lua[[require('impatient')]]
      local imp_load_dur = load_no_exist_mod()
      total_imp_load_dur = total_imp_load_dur + imp_load_dur
    end

    local threshold = 1.4 * total_vim_load_dur

    assert(total_imp_load_dur < threshold,
      string.format('%f > %f', total_imp_load_dur, threshold))
  end)

end)
