**WIP**

Speed up loading Lua modules in Neovim.

The expectation is that a form of this plugin will eventually be merged into Neovim core via this [PR](https://github.com/neovim/neovim/pull/15436). This plugin serves as a way for impatient users to speed up there Neovim 0.5 until the PR is merged and included in a following Neovim release at which point this plugin will be redundant.

## Description

This plugin does several things to speed up `require` in Lua.

### Restores the preloader

Neovim currently places its own loader for searching runtime files at the front of `packer.loaders`. This prevents any preloaders in `package.preload` from being used. This plugin fixes that by moving the default package preloader to run before Neovims loader.

### Implements cache for all loaded Lua modules

This is done by using `loadstring` to compile the Lua modules and stores them in a cache file. This also has the benefit of avoiding Neovims expensive module loader which uses `nvim_get_runtime_file()`. The cache is invalidated using the modified time of each modules file.

Also note that [mpack](https://luarocks.org/modules/tarruda/mpack) is required for reading and writing a cache file. Regular Neovim builds will have this built in, however if your build hasn't then you should be able to install it via [packer](https://github.com/wbthomason/packer.nvim).

The cache file is located in `$XDG_CACHE_HOME/nvim/luacache`.

### Reduces `runtimepath` during `require`

`runtimepath` contains directories for many things used by Neovim including Lua modules; the full list of what it is used for can be found using `:help 'runtimepath'`. When `require` is called, Neovim searches through every directory in `runtimepath` until it finds a match. This means it ends up searching in every plugin that doesn't have a Lua directory, which can be quite a lot and makes `require` much more expensive to run. To mitigate this, Impatient reduces `runtimepath` during `require` to only contain directories that have a Lua directory.

## Installation

[packer.nvim](https://github.com/wbthomason/packer.nvim):
```lua
-- Is using a standard Neovim install, i.e. built from source or using a
-- provided appimage.
use 'lewis6991/impatient.nvim'

-- If your Neovim install doesn't include mpack, e.g. if installed via
-- Homebrew, then you need to also install mpack from luarocks.
use {'lewis6991/impatient.nvim', rocks = 'mpack'}
```

## Setup

impatient needs to be setup before any other lua plugin is loaded so it is recommended you add the following near the start of your `init.vim`.

```viml
require('impatient')
```

## Commands

`:LuaCacheClear`:

Delete the current cache file. A new cache file will be created the next time you load Neovim.

`:LuaCacheLog`:

View log of impatient.

## Credit

All credit goes to @bfredl who implemented the majority of this plugin in https://github.com/neovim/neovim/pull/15436.
