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

return CachePack
