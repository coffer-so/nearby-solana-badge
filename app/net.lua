-- SPDX-License-Identifier: MIT
-- Serialised, bounded public-profile requests. All profile data stays in RAM.
local Social = require('social')
local Text = require('text')
local Net = {}
Net.__index = Net
local clean=Text.clean
local function handle(s)
  if type(s) ~= 'string' then return nil end
  s = s:gsub('^@', '')
  if #s > 0 and #s <= 15 and s:match('^[A-Za-z0-9_]+$') then return s end
end
function Net.new(model, changed)
  return setmetatable({model=model, changed=changed or function() end,
    queue={}, current=nil, paused=false, stopped=false, blockedUntil=0,
    status='', cache={}, cacheOrder={}}, Net)
end
function Net:request(e, kind, force)
  if force then self.blockedUntil=0 end
  if self.stopped or not e or e.loading then return end
  local now = sys.millis()
  if not force and now < (e.retryAt or 0) then return end
  if #self.queue >= 16 then return end
  e.loading = true
  self.queue[#self.queue+1] = {entry=e, kind=kind or 'badge', force=force==true}
end
function Net:finish(message)
  local job = self.current
  if job then
    job.entry.loading = false
    job.entry.retryAt = sys.millis() + (message and 60000 or 600000)
    if message then job.entry.warning = message end
    if job.waiting then
      self.blockedUntil=sys.millis()+60000
      job.entry.warning='Wi-Fi needed for X profiles'
    end
  end
  self.current, self.status = nil, ''
  if self.paused then pcall(mesh.resume); self.paused=false end
  self.changed()
end
function Net:apply(e, data)
  if type(data) ~= 'table' then return end
  e.name = clean(data.name, 80) ~= '' and clean(data.name, 80) or e.name
  e.bio, e.website = clean(data.bio, 640), clean(data.website, 256)
  e.avatarURL = type(data.avatarURL)=='string' and data.avatarURL or nil
end
function Net:loadX(job)
  local e = job.entry
  if not handle(e.handle) then self:finish('No linked X account'); return end
  local cached = self.cache[e.handle:lower()]
  if not job.force and cached and sys.millis() - cached.at < 600000 then
    self:apply(e,cached.data);e.image=cached.image;self:finish();return
  end
  self.status='Loading public X profile';self.changed()
  local sent=pcall(Social.fetch,e.handle,function(ok,data)
    if self.stopped or self.current~=job then return end
    if not ok or type(data)~='table' then
      self:finish('X: '..clean(type(data)=='string' and data or 'profile unavailable',60));return
    end
    if data.handle~=nil and (not handle(data.handle) or data.handle:lower()~=e.handle:lower()) then
      self:finish('Profile identity mismatch');return
    end
    self:apply(e,data);e.warning=nil
    local key=e.handle:lower()
    if not self.cache[key] then self.cacheOrder[#self.cacheOrder+1]=key end
    self.cache[key]={at=sys.millis(),data=data}
    while #self.cacheOrder>24 do self.cache[table.remove(self.cacheOrder,1)]=nil end
    self.changed()
    if not e.avatarURL then self:finish();return end
    self.status='Loading avatar'
    local avatarSent=pcall(Social.avatar,e.avatarURL,function(imageOK,img)
      if self.stopped or self.current~=job then return end
      if imageOK then e.image=img;if self.cache[key] then self.cache[key].image=img end
      else e.warning='Avatar: '..clean(type(img)=='string' and img or 'unavailable',60) end
      self:finish()
    end)
    if not avatarSent and self.current==job then self:finish('Avatar unavailable') end
  end,job.force)
  if not sent and self.current==job then self:finish('X profile unavailable') end
end
function Net:start(job)
  job.deadline=sys.millis()+35000
  local e=job.entry
  if job.kind=='x' then self:loadX(job);return end
  self.status='Matching badge to X profile';self.changed()
  local function done(ok,data)
    if self.stopped or self.current~=job then return end
    if not ok or type(data)~='table' then self:finish('Badge profile unavailable');return end
    if job.kind=='badge' then
      if not self.model:profile(e.id,data) then self:finish('Badge profile mismatch');return end
    else
      e.name=clean(data.xName or data.name,80)
      e.handle=handle(data.x)
      e.verified=true
    end
    if not handle(e.handle) then self:finish('No linked X account');return end
    self:loadX(job)
  end
  local ok = pcall(function()
    if job.kind=='me' then profile.me(done) else profile.get(e.id,done) end
  end)
  if not ok then self:finish('Profile permission unavailable') end
end
function Net:step()
  if self.stopped then return end
  if Social.step then Social.step() end
  local now=sys.millis()
  local job=self.current
  if job then
    if now>job.deadline then self:finish('Network timeout');return end
    if job.waiting and badge.online() then job.waiting=false;self:start(job) end
    return
  end
  if now<self.blockedUntil or #self.queue==0 then return end
  job=table.remove(self.queue,1);self.current=job;job.deadline=now+35000
  if badge.online() then self:start(job);return end
  local info=mesh.info and mesh.info() or {}
  if not info.paused then local ok=pcall(mesh.pause);self.paused=ok end
  job.waiting=true;job.deadline=now+12000
  self.status='Connecting Wi-Fi for profiles';self.changed()
end
function Net:close()
  self.stopped=true
  for _,job in ipairs(self.queue) do job.entry.loading=false end
  self.queue={}
  if self.current then self.current.entry.loading=false end
  self.current=nil
  if self.paused then pcall(mesh.resume);self.paused=false end
end
return Net
