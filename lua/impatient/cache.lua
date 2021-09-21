local M = {}

function M:init()
  self.stmt = require("sqlite.stmt")
  self.clib = require('sqlite.defs')
  self.db = require('sqlite.db').new(vim.fn.stdpath('cache') ..'/luacache.db')
  self.db:with_open(function ()
    self.db:create("luacache", { id = true, chunk = "blob", size = "integer", ensure = true })
  end)
end

function M:save(chunk)
  return self.db:with_open(function ()
    local statement = "replace into luacache(id, chunk, size) values(?, ?, ?)"
    local sobj = self.stmt:parse(self.db.conn, statement)
    self.clib.bind_int(sobj.pstmt, 1, 1)
    self.clib.bind_blob(sobj.pstmt, 2, chunk, #chunk + 1, nil)
    self.clib.bind_int(sobj.pstmt, 3, #chunk)
    sobj:step()
    sobj:bind_clear()
    return sobj:finalize()
  end)
end

function M:dump()
  return self.db:with_open(function ()
    local ret = {}
    local stmt = self.stmt:parse(self.db.conn, "select * from luacache where id = 1")
    stmt:step()
    for i = 0, stmt:nkeys() - 1 do
      ret[stmt:key(i)] = stmt:val(i)
    end
    local chunk = self.clib.to_str(ret.chunk, ret.size)
    stmt:reset()
    stmt:finalize()
    return chunk
  end)
end

function M:clear()
  return self.db:with_open(function ()
    return self.db:delete("luacache")
  end)
end

return M
