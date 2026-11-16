-- SPDX-License-Identifier: MIT
local app=assert(arg[1]);package.path=app..'/?.lua;'..package.path
local checks=0
local function check(b,m) checks=checks+1;assert(b,m) end
local now,online,paused,scanning=0,true,false,false
local peers,objects,toasts={}, {},{}
local inputCallback,scanCallback,exitCalled
local peak,count=0,0
local function bounded(fn,...)
  local args={...};count=0
  debug.sethook(function() count=count+100;assert(count<190000,'callback VM budget') end,'',100)
  local ok,res=pcall(fn,table.unpack(args));debug.sethook()
  peak=math.max(peak,count);assert(ok,res);return res
end
local function object(kind,x,y,w,h,text)
  check(type(x)=='number' and x==math.floor(x),'integer x')
  check(type(y)=='number' and y==math.floor(y),'integer y')
  check(x>=0 and y>=0 and x<320 and y<218,'visible position')
  check(not w or x+w<=320,'width within app')
  check(not h or y+h<=218,'height within app')
  if text then check(utf8.len(text)~=nil,'valid UTF8 UI text') end
  local o={kind=kind,textValue=text,x=x,y=y,w=w,h=h};objects[#objects+1]=o
  check(#objects<=128,'native UI object cap')
  function o:text(v)self.textValue=v end
  function o:remove()end
  return o
end
ui={W=320,H=218,
  bg=function()end,
  clear=function()objects={}end,
  label=function(x,y,s,o) return object('label',x,y,o.w,nil,s) end,
  rect=function(x,y,w,h,o)return object('rect',x,y,w,h)end,
  image=function(x,y,source,opts)
    if type(source)=='table' then
      check(type(opts.palette)=='table','independent avatar palette')
      for _,row in ipairs(source)do check(#row<=24,'bounded avatar width')end
    end
    return object('image',x,y)
  end,
  qr=function(x,y,size,url)check(url:match('^https?://'),'safe QR URL');return object('qr',x,y,size,size)end,
  input=function(_,_,cb)inputCallback=cb end,
  toast=function(s)toasts[#toasts+1]=s end,
}
sys={millis=function()return now end,exit=function()exitCalled=true end,
 memory=function()return{used=0,max=6291456}end}
badge={id=function()return 'SELF00' end,online=function()return online end}
mesh={
 nearby=function()return peers end,
 info=function()return{channel=149,paused=paused,scanning=scanning,online=online}end,
 pause=function()paused=true;return true end,
 resume=function()paused=false;return true end,
 scan=function(opts,cb)check(opts.band=='all','both radio bands scanned');scanning=true;scanCallback=cb;return true end,
 channel=function(ch)check(ch==6,'strongest badge group chosen');return true end,
}
profile={
 get=function(id,cb)cb(true,{x='sample_user',xName='Synthetic profile',level=7})end,
 me=function(cb)cb(true,{x='sample_user',xName='Synthetic self'})end,
}
package.loaded.social={
 fetch=function(h,cb)
  check(h=='sample_user' or h=='manual_user','normalised public handle')
  cb(true,{name='Synthetic profile',bio=string.rep('A public synthetic bio. ',12)..'Привет 世界',website='https://example.com/public',avatarURL='https://example.com/avatar.gif'})
 end,
 avatar=function(_,cb)cb(true,{rows={'ab','ba'},palette={a=0xFF0000,b=0xFFFFFF},w=2,h=2})end,
}
storage={get=function()error('must not read persisted people')end,set=function()error('must not persist people')end}
local function contains(text)
 for _,o in ipairs(objects)do if o.textValue and o.textValue:find(text,1,true)then return true end end
 return false
end
local function tick(ms)now=now+ms;bounded(on_tick,ms)end
local function key(k,rep)bounded(on_key,k,rep or false);tick(30)end
bounded(dofile,app..'/main.lua')
check(contains('made by Coffer team') and contains('yield on RWA baskets'),'header branding')
check(contains('coffer.so') and contains('No badges in range yet'),'empty state/footer')
check(on_key('back')==false,'CANCEL exits from list')
key('select');tick(1000)
check(contains('Synthetic profile'),'own X profile')
check(contains('X PROFILE'),'manual profiles never claim physical signal')
key('right');check(contains('BIO'),'full bio tab')
for i=1,25 do key('down',true)end
check(contains('Привет') or contains('public synthetic'),'bio can scroll to end')
key('right');check(contains('Website'),'website tab')
key('select');check(contains('Scan on your phone'),'public QR view')
key('up');check(contains('X profile'),'QR can switch to the X profile')
key('down');check(contains('Website'),'QR can switch to the public website')
key('back')
key('right');check(type(inputCallback)=='function','manual lookup opens keyboard')
local behindKeyboard=objects;tick(3000)
check(objects==behindKeyboard,'background refresh preserves the focused keyboard')
bounded(inputCallback,'@manual_user');tick(1000)
check(contains('X PROFILE'),'manual lookup no fake metres')
key('back');key('right');bounded(inputCallback,'javascript:bad');tick(30)
check(toasts[#toasts]:find('letters',1,true),'malformed handle rejected')
for i=1,16 do peers[i]={id=string.format('N%05d',i),name='ordinary badge',kind='badge',rssi=-40-i,level=i}end
peers[17]={id='SELF00',name='self',kind='badge',rssi=-20}
peers[18]={id='BEACON',kind='beacon',rssi=-30}
tick(1000)
check(contains('badges'),'ordinary HELLO list')
for i=1,18 do tick(1000)end
check(contains('@sample_user'),'badge ID matched to linked X')
check(contains('very close'),'live badge range shown before pause')
paused=true;tick(1000)
check(contains('paused') and not contains('very close'),'paused list hides stale proximity')
paused=false;scanning=true;tick(1000)
check(contains('paused') and not contains('very close'),'channel scan list hides stale proximity')
scanning=false;tick(1000)
check(contains('very close'),'list proximity returns after radio resumes')
key('select');check(not contains('X PROFILE'),'physical badge opens signal view')
local initialObjects=#objects
for i=1,20 do
 for _,p in ipairs(peers)do if p.kind=='badge' and p.id~='SELF00' then p.rssi=math.max(-90,math.min(-30,(p.rssi or -60)+((i%2==0)and 2 or -1)))end end
 tick(1000)
end
check(#objects<=initialObjects+4,'bounded live signal redraw')
local returningPeers=peers;peers={};tick(31000)
check(contains('SIGNAL PAUSED') and not contains('RSSI '),'expired open profile hides its old signal')
peers=returningPeers;tick(1000)
check(contains('RSSI ') and not contains('SIGNAL PAUSED'),'returning badge restores the open profile signal')
for _=1,20 do key('right');key('down');key('left');key('back');key('down');key('select')end
key('back');peers={};tick(31000);tick(31000)
check(contains('No badges in range yet'),'lost peers expire')
key('left');check(type(scanCallback)=='function','all-channel scan available')
scanning=false;bounded(scanCallback,{{channel=149,badges=0},{channel=6,badges=2}});tick(30)
online=false;key('select');tick(1000);tick(13000)
check(not paused,'failed network attempt resumes radio')
bounded(on_exit);check(not paused,'exit returns radio')
on_tick,on_exit,on_key=nil,nil,nil;objects={}
sys.memory=function()return{used=0,max=98304}end
bounded(dofile,app..'/main.lua')
check(contains('Nearby needs Solana OS 2.0+'),'legacy host fails gracefully without loading caches')
check(on_tick==nil and on_key('back')==false,'legacy host can exit without network tasks')
print('app_spec: '..checks..' UI/lifecycle/input checks; peak '..peak..'/200000 VM')
