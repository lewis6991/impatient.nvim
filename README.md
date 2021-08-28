
Cache for lua modules.

**WIP**

## Installation

[packer.nvim](https://github.com/wbthomason/packer.nvim):
```lua
use 'lewis6991/impatient.nvim'
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
