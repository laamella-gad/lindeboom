#!/usr/bin/env lua
-- Lua 5.4 syntax sample used by `tests/tlua.nim`.
--[[
A long comment. The sequences ]=] and ]==] do not close a level-0 bracket.
]]

local a, b = 1, 2.5
local c <const> = 0x1.8p1
local d <close> = io.open("file.txt", "r")

local numbers = {
  0, 42, 3.14, .5, 1e10, 0x10, 0xA.8p-2,
  -1, 2,
}

local strings = {
  "double \"quoted\" \n \x41 \u{1F600} \065",
  'single \'quoted\'',
  [[long string with ]=] and ]==] and \n]],
  [==[another ]=] long string]==],
}

local function fact(n, ...)
  if n <= 1 then
    return 1
  elseif n == 2 then
    return 2
  else
    return n * fact(n - 1, ...)
  end
end

function T.m(a, b, ...)
  local x = a.b[c] + a:b(c)
  local y = (a + b) * #a ^ -2
  local z = a .. b .. c
  local w = a | b & c ~ d << e
  local q = not a == b and c or d
  return x, y, z, w, q
end

local obj = { [a] = 1, name = 2, 3, 4, }
obj.field, obj[key] = 5, 6

for i = 1, 10, 2 do
  if i % 2 == 0 then break end
end

for k, v in pairs(obj) do
  while v do
    v = v - 1
  end
end

repeat
  a = a + 1
until a > 10

do
  ::again::
  if a < 0 then goto again end
end

local f = function(x) return x * 2 end
f(1)
T:m(2)
f {x = 1}
f "s"
f[[s]]

;
return a, b
