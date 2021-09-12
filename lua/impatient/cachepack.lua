local ffi = require('ffi')

-- using double for packing/unpacking numbers has no conversion overhead
-- 32-bit ARM causes a bus error when casting to double, so use int there
local number_t = jit.arch ~= "arm" and "double" or "int"
ffi.cdef("typedef " .. number_t .. " number_t;")

local c_number_t = ffi.typeof "number_t[1]"
local c_sizeof_number_t = ffi.sizeof "number_t"

local CachePack = {}

function CachePack.pack(cache)
  local buf = {}

  local function write_number(num)
    buf[#buf+1] = ffi.string(c_number_t(num), c_sizeof_number_t)
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
    local res = ffi.cast("number_t*", buf + buf_pos)[0]
    buf_pos = buf_pos + c_sizeof_number_t
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

return CachePack
