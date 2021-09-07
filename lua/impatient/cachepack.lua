local ffi = require('ffi')

local M = {}

-- using double for packing/unpacking numbers has no conversion overhead
local c_double = ffi.typeof("double[1]")
local sizeof_c_double = ffi.sizeof("double")

local function write_number(buf, num)
  buf[#buf+1] = ffi.string(c_double(num), sizeof_c_double)
end

local function write_string(buf, str)
  write_number(buf, #str)
  buf[#buf+1] = str
end

local function create_input_buffer(str)
  return {
    ptr = ffi.new("const char[?]", #str, str),
    pos = 0,
    size = #str
  }
end

local function read_number(buf)
  if (buf.size < buf.pos) then error("buffer access violation") end
  local res = ffi.cast("double*", buf.ptr + buf.pos)[0]
  buf.pos = buf.pos + sizeof_c_double
  return res
end

local function read_string(buf)
  local len = read_number(buf)
  local res = ffi.string(buf.ptr + buf.pos, len)
  buf.pos = buf.pos + len

  return res
end

function M.pack(cache)
  local total_keys = vim.tbl_count(cache)
  local buf = {}

  write_number(buf, total_keys)
  for k,v in pairs(cache) do
    write_string(buf, k)
    write_string(buf, v[1] or "")
    write_number(buf, v[2] or 0)
    write_string(buf, v[3] or "")
  end

  return table.concat(buf)
end

function M.unpack(str)
  if str == nil or #str == 0 then
    return {}
  end

  local buf = create_input_buffer(str)
  local cache = {}

  local total_keys = read_number(buf)
  for _ = 1, total_keys do
    local k = read_string(buf)
    cache[k] = {
      read_string(buf),
      read_number(buf),
      read_string(buf)
    }
  end

  return cache
end

return M
