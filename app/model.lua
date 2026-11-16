-- SPDX-License-Identifier: MIT
-- Public metadata and approximate signal history, kept only in bounded RAM.
local M={MAX_ENTRIES=32,MAX_INPUT=64,STALE_MS=30000}
local State={};State.__index=State
local floor,min=math.floor,math.min
local function finite(n) return type(n)=='number' and n==n and n~=math.huge and n~=-math.huge end
local function id(s) return type(s)=='string' and #s==6 and s:match('^[A-Za-z0-9]+$')~=nil end
local function handle(s)
  if type(s)~='string' or #s>16 then return nil end
  s=s:gsub('^@','')
  if #s>0 and #s<=15 and s:match('^[A-Za-z0-9_]+$') then return s:lower() end
end
-- Validate UTF-8 in one bounded pass, without retaining a huge incoming string.
local function clean(s,limit)
  if type(s)~='string' then return '' end
  s=s:sub(1,limit)
  if not s:find('[\128-\255]') then
    return s:gsub('[%z\1-\31\127]',' '):gsub('^%s+',''):gsub('%s+$','')
  end
  local out,i={},1
  while i<=#s do
    local b=s:byte(i)
    local n=b<128 and 1 or (b>=194 and b<=223 and 2 or (b>=224 and b<=239 and 3 or (b>=240 and b<=244 and 4 or 0)))
    local good=n>0 and i+n-1<=#s
    for j=1,n-1 do local c=s:byte(i+j);if not c or c<128 or c>191 then good=false end end
    local c=s:byte(i+1)
    if (b==224 and (not c or c<160)) or (b==237 and c and c>159)
      or (b==240 and (not c or c<144)) or (b==244 and c and c>143) then good=false end
    if good then
      out[#out+1]=(b<32 or b==127) and ' ' or s:sub(i,i+n-1)
      i=i+n
    else i=i+1 end
  end
  return table.concat(out):gsub('^%s+',''):gsub('%s+$','')
end
local function level(n) if finite(n) and n>=0 then return floor(min(n,99999)) end end
local function signal(n) if finite(n) and n>=-100 and n<=-20 then return floor(n+0.5) end end
local function url(s,limit,https)
  if type(s)~='string' or #s>limit or s:find('[%z\1-\32\127]') then return nil end
  local scheme,host=s:match('^(https?)://([^/?#]+)')
  if not scheme or (https and scheme~='https') or not host:match('^[A-Za-z0-9.%-]+$') then return nil end
  return s
end
local function identity(data,badge)
  for _,key in ipairs({'badge','badgeId'}) do
    if rawget(data,key)~=nil and rawget(data,key)~=badge then return false end
  end
  local value=rawget(data,'id')
  return not id(value) or value==badge
end
local function score(e)
  if not e.present then return -3000 end
  if e.bridged then return -2000 end
  return e.smoothed or e.rssi or -1000
end
local function stronger(a,b)
  local x,y=score(a),score(b)
  return x>y or (x==y and a.id<b.id)
end
local function estimate(e)
  if not e.present then return 'Not currently detected' end
  if e.bridged then return 'Bridge: no proximity estimate' end
  local s=e.smoothed
  if not s then return 'Estimate unavailable' end
  if s>=-50 then return 'Estimate: very close'
  elseif s>=-65 then return 'Estimate: nearby'
  elseif s>=-80 then return 'Estimate: farther away'
  else return 'Estimate: weak / far' end
end
local function absent(e)
  -- Open profiles can retain this object after it leaves the bounded table.
  e.present=false;e.rssi=nil;e.smoothed=nil;e._anchor=nil;e._anchorAt=nil
  e.trend='STEADY';e.rangeText=estimate(e)
end
local function apply(e,p,now)
  e.present,e.lastSeen,e.bridged=true,now,p.bridged
  e.radioName=p.name
  if not e.profilesFetched and not e.verified then
    e.name=p.name~='' and p.name or e.id;e.level=p.level or e.level
  end
  e.rssi=not p.bridged and p.rssi or nil
  if not e.rssi then
    e.smoothed,e._anchor,e._anchorAt=nil,nil,nil;e.trend='STEADY'
  else
    e.smoothed=e.smoothed and e.smoothed+(e.rssi-e.smoothed)*0.3 or e.rssi
    if not e._anchorAt then e._anchor,e._anchorAt=e.smoothed,now end
    if now-e._anchorAt>=5000 then
      local delta=e.smoothed-e._anchor
      e.trend=delta>=3 and 'HOTTER' or (delta<=-3 and 'COLDER' or 'STEADY')
      e._anchor,e._anchorAt=e.smoothed,now
    end
  end
  e.rangeText=estimate(e)
end
function M.new() return setmetatable({entries={},_now=0},State) end
function State:get(badge) return id(badge) and self.entries[badge] or nil end
function State:list()
  local out={}
  for _,e in pairs(self.entries) do out[#out+1]=e end
  table.sort(out,stronger)
  return out
end
function State:merge(peers,now,selfID)
  if finite(now) and now>=self._now and now<=2147483647 then self._now=now end
  now=self._now
  local records,seen={},{}
  if type(peers)=='table' then for i=1,M.MAX_INPUT do
    local p=rawget(peers,i)
    if type(p)=='table' then
      local badge=rawget(p,'id')
      if rawget(p,'kind')=='badge' and id(badge) and badge~=selfID and not seen[badge] then
        local r={id=badge,name=clean(rawget(p,'name'),80),rssi=signal(rawget(p,'rssi')),
          level=level(rawget(p,'level')),bridged=rawget(p,'bridged')==true,present=true}
        records[#records+1]=r;seen[badge]=r
      end
    end
  end end
  local count=0
  for badge,e in pairs(self.entries) do
    if badge==selfID or (not seen[badge] and now-e.lastSeen>=M.STALE_MS) then
      absent(e);self.entries[badge]=nil
    else
      count=count+1
      if not seen[badge] then
        absent(e)
      end
    end
  end
  -- Refresh current entries before ranking newcomers, so old RSSI never wins.
  for _,p in ipairs(records) do local e=self.entries[p.id];if e then apply(e,p,now) end end
  table.sort(records,stronger)
  for _,p in ipairs(records) do if not self.entries[p.id] then
    local victim
    if count>=M.MAX_ENTRIES then
      for _,e in pairs(self.entries) do if not victim or stronger(victim,e) then victim=e end end
    end
    if not victim or stronger(p,victim) then
      if victim then absent(victim);self.entries[victim.id]=nil;count=count-1 end
      local e={id=p.id,name=p.id,bio='',website='',level=0,trend='STEADY',profilesFetched=false}
      apply(e,p,now);self.entries[p.id]=e;count=count+1
    end
  end end
  return self:list()
end
function State:profile(badge,data)
  local e=self:get(badge)
  if not e or type(data)~='table' or not identity(data,badge) then return false end
  local n,xn,x=rawget(data,'name'),rawget(data,'xName'),rawget(data,'x')
  local lv=level(rawget(data,'level'))
  if type(n)~='string' and type(xn)~='string' and type(x)~='string' and not lv then return false end
  local linked=handle(x)
  if linked~=e.handle then e.bio,e.website,e.avatarURL,e.image='', '',nil,nil end
  e.handle=linked
  local display=clean(xn,80)
  e.xName=display~='' and display or nil
  if display=='' then display=clean(n,80) end
  e.name=display~='' and display or (e.radioName~='' and e.radioName or e.id)
  if lv then e.level=lv end
  e.profilesFetched,e.verified=true,true
  return true
end
function State:details(badge,data)
  local e=self:get(badge)
  if not e or type(data)~='table' or not identity(data,badge) then return false end
  local linked=handle(rawget(data,'handle'))
  if not linked or linked~=e.handle then return false end
  local display=clean(rawget(data,'name'),80)
  if display~='' then e.name=display;e.xName=display end
  e.bio=clean(rawget(data,'bio'),640)
  e.website=url(rawget(data,'website'),256,false) or ''
  e.avatarURL=url(rawget(data,'avatarURL'),512,true)
  return true
end
return M
