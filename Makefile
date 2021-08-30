.DEFAULT_GOAL := test

NEOVIM_BRANCH := master

FILTER=.*

neovim:
	git clone --depth 1 https://github.com/neovim/neovim --branch $(NEOVIM_BRANCH)
	make -C $@

export VIMRUNTIME=$(PWD)/neovim/runtime

.PHONY: test
test: neovim
	neovim/.deps/usr/bin/busted \
		-v \
		--lazy \
		--helper=$(PWD)/test/preload.lua \
		--output test.busted.outputHandlers.nvim \
		--lpath=$(PWD)/neovim/?.lua \
		--lpath=$(PWD)/neovim/build/?.lua \
		--lpath=$(PWD)/neovim/runtime/lua/?.lua \
		--lpath=$(PWD)/?.lua \
		--lpath=$(PWD)/lua/?.lua \
		--filter=$(FILTER) \
		$(PWD)/test

	-@stty sane
