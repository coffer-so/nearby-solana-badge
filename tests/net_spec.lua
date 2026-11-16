-- SPDX-License-Identifier: MIT
-- Synthetic public identities only. No network, passwords, or real people data.
local root=arg[1] or 'app'
package.path=root..'/?.lua;'..package.path
local Model=dofile(root..'/model.lua')
local passed,failed=0,{}
local function test(name,fn)
  local ok,why=pcall(fn)
  if ok then passed=passed+1 else failed[#failed+1]=name..': '..tostring(why) end
end
local function fixture(opts)
  opts=opts or {}
  local f={time=0,online=opts.online~=false,pauses=0,resumes=0,changed=0,
    profiles={},xs={},avatars={},model=Model.new()}
  sys={millis=function() return f.time end}
  badge={online=function() return f.online end}
  mesh={info=function() return {paused=opts.alreadyPaused or false} end,
    pause=function() f.pauses=f.pauses+1 end,resume=function() f.resumes=f.resumes+1 end}
  profile={get=function(id,cb)
      if opts.permissionError then error('permission denied') end
      f.profiles[#f.profiles+1]={id=id,cb=cb}
    end,me=function(cb)
      if opts.permissionError then error('permission denied') end
      f.profiles[#f.profiles+1]={me=true,cb=cb}
    end}
  package.loaded.social={fetch=function(handle,cb,force)
      if opts.socialThrow then error('network adapter unavailable') end
      f.xs[#f.xs+1]={handle=handle,cb=cb,force=force}
    end,avatar=function(url,cb)
      if opts.avatarThrow then error('image adapter unavailable') end
      f.avatars[#f.avatars+1]={url=url,cb=cb}
    end}
  local Net=dofile(root..'/net.lua')
  f.net=Net.new(f.model,function() f.changed=f.changed+1 end)
  function f:entry(id,handle)
    self.model:merge({{id=id,kind='badge',name='Synthetic',rssi=-55}},self.time)
    local e=assert(self.model:get(id));e.handle=handle;return e
  end
  function f:step(time,online)
    if time then self.time=time end
    if online~=nil then self.online=online end
    self.net:step()
  end
  function f:p(i,ok,data) self.profiles[i].cb(ok,data) end
  function f:x(i,ok,data) self.xs[i].cb(ok,data) end
  function f:a(i,ok,data) self.avatars[i].cb(ok,data) end
  return f
end
local function size(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
local function public(handle,extra)
  local d={handle=handle,name='Synthetic Name',bio='Synthetic bio',website='https://example.com'}
  for k,v in pairs(extra or {}) do d[k]=v end
  return d
end
test('queue cap, deduplication and one in flight',function()
  local f=fixture()
  for i=1,30 do f.net:request(f:entry(('B%05d'):format(i))) end
  assert(#f.net.queue==16)
  f:step();assert(#f.profiles==1 and #f.net.queue==15)
  for _=1,10 do f:step() end
  assert(#f.profiles==1 and f.net.current)
  f.net:request(f.net.current.entry);assert(#f.net.queue==15)
  f:p(1,false,'offline');f:step();assert(#f.profiles==2)
end)
test('success resumes owned radio and mutates original entry',function()
  local f=fixture({online=false});local e=f:entry('AAAAAA')
  f.net:request(e);f:step();assert(f.pauses==1 and not f.profiles[1])
  f:step(1000,true);f:p(1,true,{name='Synthetic',x='alice',xName='Тест 🛰',level=3})
  assert(f.xs[1].handle=='alice' and f.model:get(e.id)==e)
  f:x(1,true,public('alice'))
  assert(e.name=='Synthetic Name' and e.bio=='Synthetic bio' and not e.loading)
  assert(f.resumes==1 and not f.net.current and e.retryAt==601000)
end)
test('profile/network errors restore radio',function()
  for _,stage in ipairs({'profile','social','avatar'}) do
    local f=fixture({online=false});local e=f:entry('AAAAAA')
    f.net:request(e);f:step();f:step(1000,true)
    if stage=='profile' then f:p(1,false,'denied') else
      f:p(1,true,{x='alice',name='Synthetic'})
      if stage=='social' then f:x(1,false,'timeout') else
        f:x(1,true,public('alice',{avatarURL='https://pbs.twimg.com/profile_images/test.png'}))
        f:a(1,false,'unavailable')
      end
    end
    assert(f.resumes==1 and not e.loading and not f.net.current and e.warning)
  end
end)
test('offline timeout backs off queue and force overrides it',function()
  local f=fixture({online=false});local a,b=f:entry('AAAAAA'),f:entry('BBBBBB')
  f.net:request(a);f.net:request(b);f:step();f:step(12001)
  assert(f.resumes==1 and not a.loading and a.retryAt==72001 and f.net.blockedUntil==72001)
  f:step(13000);assert(f.pauses==1 and not f.net.current)
  f.net:request(a,'badge',true);f:step();assert(f.pauses==2 and f.net.current)
end)
test('request timeout, exit and stale asynchronous answers',function()
  local f=fixture({online=false});local e=f:entry('AAAAAA')
  f.net:request(e);f:step();f:step(1000,true)
  local delayed=f.profiles[1].cb
  f:step(36001);assert(f.resumes==1 and not e.loading and not f.net.current)
  delayed(true,{x='stale',name='Wrong'});assert(not e.handle and #f.xs==0)
  f.net:request(e,'badge',true);f:step(37000,false);f:step(38000,true)
  f:p(2,true,{x='alice',name='Synthetic'})
  local lateX=f.xs[1].cb
  local queued=f:entry('BBBBBB');f.net:request(queued)
  f.net:close();assert(f.resumes==2 and not e.loading and not queued.loading)
  lateX(true,public('alice'));assert(e.bio=='' and not f.net.current)
  f:step(40000);assert(#f.net.queue==0)
end)
test('avatar success is cached and late avatar after close ignored',function()
  local f=fixture();local e=f:entry('AAAAAA','alice')
  f.net:request(e,'x');f:step()
  f:x(1,true,public('alice',{avatarURL='https://pbs.twimg.com/profile_images/test.png'}))
  local image={rows={'a'},palette={a=0x123456}}
  f:a(1,true,image);assert(e.image==image and f.net.cache.alice.image==image)
  local b=f:entry('BBBBBB','bob');f.net:request(b,'x');f:step()
  f:x(2,true,public('bob',{avatarURL='https://pbs.twimg.com/profile_images/other.png'}))
  f.net:close();f:a(2,true,image);assert(not b.image)
end)
test('already paused radio is not resumed by this owner',function()
  local f=fixture({online=false,alreadyPaused=true});local e=f:entry('AAAAAA','alice')
  f.net:request(e,'x');f:step();f:step(1000,true);f:x(1,true,public('alice'))
  assert(f.pauses==0 and f.resumes==0)
end)
test('permissions failure cleans up',function()
  local f=fixture({online=false,permissionError=true});local e=f:entry('AAAAAA')
  f.net:request(e);f:step();f:step(1000,true)
  assert(f.resumes==1 and not e.loading and not f.net.current and e.warning=='Profile permission unavailable')
end)
test('asynchronous adapter throws release the owned radio',function()
  for _,opts in ipairs({{socialThrow=true},{avatarThrow=true}}) do
    opts.online=false
    local f=fixture(opts);local e=f:entry('AAAAAA')
    f.net:request(e);f:step();f:step(1000,true)
    local ok=pcall(function()
      f:p(1,true,{x='alice',name='Synthetic'})
      if opts.avatarThrow then
        f:x(1,true,public('alice',{avatarURL='https://pbs.twimg.com/profile_images/test.png'}))
      end
    end)
    assert(ok and f.resumes==1 and not e.loading and not f.net.current and e.warning,
      'adapter throw escaped or retained the radio/loading state')
  end
end)
test('invalid X handles never reach Social',function()
  for _,h in ipairs({'','@@bad','bad handle','long_handle_name_123','用户',false}) do
    local f=fixture();local e=f:entry('AAAAAA',h);f.net:request(e,'x');f:step()
    assert(#f.xs==0 and not f.net.current and not e.loading and e.warning)
  end
end)
test('malformed public profile cannot reuse an old handle',function()
  local f=fixture();local e=f:entry('AAAAAA','old_handle')
  f.net:request(e);f:step();f:p(1,true,{badge='BBBBBB',x='wrong',name='Wrong person'})
  assert(#f.xs==0 and not f.net.current and e.warning,'rejected model profile still fetched X metadata')
end)
test('malformed successful Social data is not cached',function()
  for _,bad in ipairs({false,'invalid',17}) do
    local f=fixture();local e=f:entry('AAAAAA','alice');f.net:request(e,'x');f:step();f:x(1,true,bad)
    assert(not f.net.cache.alice and e.warning and not e.loading,'invalid metadata cached as success')
  end
end)
test('Social handle must match the requested person',function()
  local f=fixture();local e=f:entry('AAAAAA','alice');f.net:request(e,'x');f:step()
  f:x(1,true,public('someone_else'))
  assert(e.name~='Synthetic Name' and not f.net.cache.alice and e.warning,'wrong-person details were accepted')
end)
test('Wi-Fi join gets a fresh network-request deadline',function()
  local f=fixture({online=false});local e=f:entry('AAAAAA')
  f.net:request(e);f:step();f:step(11000,true);f:p(1,true,{x='alice',name='Synthetic'})
  f:step(13000)
  assert(f.net.current and e.loading,'Wi-Fi join consumed the profile/HTTP request deadline')
  f:x(1,true,public('alice'));assert(not f.net.current and f.resumes==1)
end)
test('UTF-8 full names and biography are bounded safely',function()
  local f=fixture();local e={id='manual'}
  f.net:request(e,'me');f:step();assert(f.profiles[1].me)
  f:p(1,true,{x='alice',xName=('名🛰'):rep(30)})
  assert(e.name~='' and #e.name<=80 and utf8.len(e.name))
  f:x(1,true,public('alice',{name=('名🛰'):rep(30),bio=('海🛰'):rep(200)}))
  assert(#e.name<=80 and utf8.len(e.name) and #e.bio<=640 and utf8.len(e.bio))
end)
test('cache bound, expiry and reuse',function()
  local f=fixture()
  for i=1,25 do
    local h='user'..i;local e=f:entry(('B%05d'):format(i),h)
    f.net:request(e,'x');f:step();f:x(i,true,public(h))
  end
  assert(size(f.net.cache)==24 and #f.net.cacheOrder==24 and not f.net.cache.user1)
  local hit=f:entry('ZZZZZZ','USER25');f.net:request(hit,'x');f:step()
  assert(#f.xs==25 and hit.bio=='Synthetic bio' and not hit.loading)
  f.net:request(hit,'x',true);f:step(600001)
  assert(#f.xs==26 and f.net.current,'expired metadata cache was reused')
end)
test('force refresh bypasses fresh metadata and avatar caches',function()
  local f=fixture();local e=f:entry('AAAAAA','alice')
  f.net:request(e,'x');f:step()
  f:x(1,true,public('alice',{avatarURL='https://pbs.twimg.com/profile_images/old.png'}))
  local first={old=true};f:a(1,true,first)
  f.net:request(e,'x',true);f:step(1000)
  assert(#f.xs==2 and f.xs[2].force==true,'force reused a fresh metadata cache')
  f:x(2,true,public('alice',{avatarURL='https://pbs.twimg.com/profile_images/new.png'}))
  assert(#f.avatars==2,'force skipped the new avatar request')
  local nextImage={new=true};f:a(2,true,nextImage)
  assert(e.image==nextImage and f.net.cache.alice.image==nextImage and not e.loading)
end)
for _,failure in ipairs(failed) do io.stderr:write('FAIL '..failure..'\n') end
print(('net_spec: %d scenarios passed, %d failed'):format(passed,#failed))
assert(#failed==0,'network lifecycle contract failures')
