-- SPDX-License-Identifier: MIT
local T={}
function T.clean(value,limit)
  if type(value)~='string' then return '' end
  local s=value:sub(1,limit or 640)
  local _,bad=utf8.len(s)
  if bad then s=s:sub(1,bad-1) end
  return s:gsub('[%z\1-\31\127]',' '):gsub('%s+',' '):match('^%s*(.-)%s*$')
end
function T.chars(s)
  local a={}
  for _,v in utf8.codes(T.clean(s,2048)) do a[#a+1]=utf8.char(v) end
  return a
end
function T.clip(s,n)
  local a=T.chars(s)
  if #a<=n then return table.concat(a) end
  return table.concat(a,'',1,math.max(0,n-3))..'...'
end
function T.wrap(s,n)
  local result,line={},''
  local function len(v) return utf8.len(v) or #v end
  for token in T.clean(s,2048):gmatch('%S+') do
    local word=token
    if line~='' and len(line)+1+len(word)>n then result[#result+1]=line;line='' end
    local chars=T.chars(word)
    while #chars>n do
      if line~='' then result[#result+1]=line;line='' end
      result[#result+1]=table.concat(chars,'',1,n)
      local rest={};for i=n+1,#chars do rest[#rest+1]=chars[i] end;chars=rest
    end
    word=table.concat(chars)
    if word~='' then line=line=='' and word or line..' '..word end
  end
  if line~='' then result[#result+1]=line end
  if #result==0 then result[1]='' end
  return result
end
function T.handle(s)
  if type(s)~='string' then return nil end
  s=s:gsub('^@','')
  if #s>0 and #s<=15 and s:match('^[A-Za-z0-9_]+$') then return s end
end
function T.url(s)
  s=T.clean(s,256)
  if s:match('^https?://[^%s]+$') then return s end
end
return T
