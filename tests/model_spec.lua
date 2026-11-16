-- SPDX-License-Identifier: MIT
local root=arg[1] or 'app'
local Model=dofile(root..'/model.lua')
local checks=0
local function check(v,why) checks=checks+1;assert(v,why) end
local function peer(id,rssi,more)
  local p={id=id,rssi=rssi,kind='badge',name='@radio',level=2}
  for k,v in pairs(more or {}) do p[k]=v end
  return p
end
local function count(s) local n=0;for _ in pairs(s.entries) do n=n+1 end;return n end
local s=Model.new()
s:merge({peer('AAAAAA',-50),peer('BBBBBB',-60),peer('CCCCCC',-40,{kind='beacon'}),
  peer('bad/id',-40),peer('short',-40),false,peer('DDDDDD',-20)},0,'DDDDDD')
check(count(s)==2 and not s:get('DDDDDD') and not s:get('CCCCCC'),'peer/self/beacon filtering')
local e=s:get('AAAAAA')
check(e.name=='@radio' and not e.handle and not e.verified,'HELLO cannot verify X identity')
check(e.rangeText:find('Estimate',1,true) and s:list()[1]==e,'estimated range or RSSI ordering')
check(not s:get(false) and not s:profile('ZZZZZZ',{x='missing'}),'invalid/unknown ID lookup')
e.retryAt=123
check(s:profile('AAAAAA',{x='@ALIce_1',name='Fallback',xName='Алиса 🛰',level=999999}), 'public profile rejected')
check(s:get('AAAAAA')==e and e.handle=='alice_1' and e.name=='Алиса 🛰' and e.xName==e.name
  and e.level==99999 and e.profilesFetched and e.verified and e.retryAt==123,'in-place canonical profile')
s:merge({peer('AAAAAA',-48,{name='forged radio name',level=1})},1000)
check(e.name=='Алиса 🛰' and e.handle=='alice_1' and e.level==99999,'HELLO overwrote verified profile')
check(not s:profile('AAAAAA',{badge='BBBBBB',x='other'}) and e.handle=='alice_1','wrong badge profile accepted')
check(not s:profile('AAAAAA',{badgeId='BBBBBB',x='other'}),'wrong badgeId profile accepted')
check(not s:profile('AAAAAA',{id='BBBBBB',x='other'}),'wrong explicit badge identity accepted')
check(not s:details('AAAAAA',{handle='bob',bio='wrong person'}),'wrong X details accepted')
check(s:details('AAAAAA',{handle='ALICE_1',name='A\0B',bio=('海'):rep(400)..'\255',
  website='https://coffer.so/path',avatarURL='https://pbs.twimg.com/profile_images/example.jpg'}),'matching X details rejected')
check(e.name=='A B' and #e.bio<=640 and utf8.len(e.bio) and not e.bio:find('\255',1,true)
  and e.website=='https://coffer.so/path' and e.avatarURL:match('^https://'),'bounded UTF-8 details')
check(s:details('AAAAAA',{handle='alice_1',bio='safe',website='javascript:alert(1)',
  avatarURL='https://user:password@example.com/image'}),'matching detail refresh rejected')
check(e.website=='' and e.avatarURL==nil,'unsafe URL retained')
e.image={}
s:profile('AAAAAA',{x='New_Handle',name='New person',level=3})
check(e.handle=='new_handle' and e.bio=='' and e.website=='' and not e.avatarURL and not e.image,'identity change retained old person data')
s:profile('AAAAAA',{name='No linked X',level=0})
check(e.handle==nil and e.name=='No linked X','unlink retained X handle')
for _,x in ipairs({'@@alice','too_long_handle_123','https://x.com/a','a b','a\n','用户名'}) do
  s:profile('AAAAAA',{x=x,name='Safe'})
  check(e.handle==nil,'invalid X handle accepted')
end
for _,bad in ipairs({false,17,'bad',function() end}) do
  check(not s:profile('AAAAAA',bad) and not s:details('AAAAAA',bad),'bad profile type accepted')
end
check(not s:profile('AAAAAA',{}) and not s:details('AAAAAA',{}),'empty metadata accepted')
s:profile('AAAAAA',{name=('я'):rep(100)..'\255',x='a'})
check(#e.name<=80 and utf8.len(e.name),'profile name split UTF-8')

-- Missing rows remain briefly for browsing, without presenting an old signal.
s=Model.new();s:merge({peer('AAAAAA',-55)},0)
local same=s:get('AAAAAA');s:merge({},1)
check(s:get('AAAAAA')==same and not same.present and same.rssi==nil and same.smoothed==nil
  and same.rangeText=='Not currently detected','missing peer presented stale proximity')
s:merge({},29999);check(s:get('AAAAAA')==same,'peer expired too early')
s:merge({},30000);check(not s:get('AAAAAA'),'peer outlived 30-second missing timeout')
s:merge({peer('AAAAAA',-55)},30001);s:merge({},30002)
s:merge({peer('AAAAAA',-60)},30003)
check(s:get('AAAAAA').present and s:get('AAAAAA').smoothed==-60,'returning peer reused old signal history')
s:merge({},0/0);s:merge({},math.huge);s:merge({},-10)
check(s:get('AAAAAA') and s._now==30003,'invalid/backward time changed expiry clock')
s:merge({peer('AAAAAA',-55)},31000,'AAAAAA');check(count(s)==0,'self entry was retained')
check(not same.present and same.rssi==nil and same.rangeText=='Not currently detected','expired external profile kept stale signal')
s=Model.new();s:merge({peer('AAAAAA',-40)},0)
local active=s:get('AAAAAA');s:merge({},57000)
check(not s:get('AAAAAA') and not active.present and not active.rssi and not active.smoothed
  and not active._anchor and not active._anchorAt and active.trend=='STEADY'
  and active.rangeText=='Not currently detected','57-second scan expiry left active profile live')
s:merge({peer('AAAAAA',-40)},58000)
active=s:get('AAAAAA');s:merge({},58001,'AAAAAA')
check(not active.present and not active.rssi,'self eviction left active profile live')
local fill={};for i=1,Model.MAX_ENTRIES do fill[i]=peer(('B%05d'):format(i),-80) end
s=Model.new();s:merge(fill,0);active=s:get('B00032')
fill[#fill+1]=peer('AAAAAA',-30);s:merge(fill,1)
check(not s:get('B00032') and not active.present and not active.rssi and not active.smoothed
  and active.rangeText=='Not currently detected','bounded eviction left active profile live')

-- Bridges and zero/invalid RSSI never acquire physical-distance wording.
s=Model.new()
s:merge({peer('AAAAAA',0,{bridged=true}),peer('BBBBBB',-45),peer('CCCCCC',0)},0)
check(s:list()[1].id=='BBBBBB','bridge zero RSSI sorted as closest')
local bridge=s:get('AAAAAA')
check(bridge.bridged and not bridge.rssi and not bridge.smoothed and bridge.rangeText:find('Bridge',1,true),
  'bridge assigned a radio distance')
check(not s:get('CCCCCC').rssi and s:get('CCCCCC').rangeText=='Estimate unavailable','zero RSSI treated as near')
for _,r in ipairs({-101,-19,math.huge,-math.huge,0/0,'-50',false}) do
  s:merge({peer('BBBBBB',r)},100)
  check(not s:get('BBBBBB').rssi and not s:get('BBBBBB').smoothed,'invalid RSSI accepted')
end
s:merge({peer('AAAAAA',-65)},200)
check(not bridge.bridged and bridge.smoothed==-65,'bridge-to-radio transition failed')
s:merge({peer('AAAAAA',-30,{bridged=true})},300)
check(not bridge.smoothed and bridge.rangeText:find('Bridge',1,true),'radio-to-bridge transition retained proximity')

-- A five-second trend uses smoothed signal; equal signals have stable ID ties.
s=Model.new();s:merge({peer('AAAAAA',-80)},0)
for t=1000,5000,1000 do s:merge({peer('AAAAAA',-40)},t) end
check(s:get('AAAAAA').trend=='HOTTER' and s:get('AAAAAA').smoothed>-80 and s:get('AAAAAA').smoothed<-40,'hotter EMA trend')
for t=6000,10000,1000 do s:merge({peer('AAAAAA',-90)},t) end
check(s:get('AAAAAA').trend=='COLDER','colder EMA trend')
for t=11000,20000,1000 do s:merge({peer('AAAAAA',-90)},t) end
check(s:get('AAAAAA').trend=='STEADY','steady EMA trend')
s=Model.new();s:merge({peer('CCCCCC',-60),peer('AAAAAA',-60),peer('BBBBBB',-60)},0)
local list=s:list();check(list[1].id=='AAAAAA' and list[2].id=='BBBBBB' and list[3].id=='CCCCCC','unstable equal-RSSI ordering')
list[1]=nil;check(count(s)==3,'list table modified the entries dictionary')

-- Huge input is inspected only through a fixed prefix and stores bounded text.
local huge={};local text=('x'):rep(100000)
for i=1,1000 do huge[i]=peer(('B%05d'):format(i),-100+(i%81),{name=text}) end
s=Model.new()
local instructions=0
debug.sethook(function() instructions=instructions+100 end,'',100)
s:merge(huge,0)
debug.sethook()
check(count(s)==Model.MAX_ENTRIES and instructions<200000,'bounded merge exceeds storage/VM budget: '..instructions)
for _,entry in ipairs(s:list()) do check(#entry.name<=80 and entry.rssi>=-100 and entry.rssi<=-20,'stored unbounded peer data') end
check(not s:get('B01000'),'merge consumed beyond its input cap')
for t=1,80 do
  s:merge({peer(('C%05d'):format(t),-50)},t*1000)
  check(count(s)<=Model.MAX_ENTRIES,'rotating peers grew the entry table')
end
s:merge('not an array',200000);check(count(s)==0,'bad snapshot type broke expiry')
print('model_spec: '..checks..' checks; bounded identity/signal/UTF-8/staleness OK; merge peak '..instructions..'/200000 VM instructions')
