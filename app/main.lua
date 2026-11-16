-- SPDX-License-Identifier: MIT
-- Nearby discovers ordinary Solana OS HELLOs; it sends no custom user records.
-- Older 96 KB hosts cannot hold the bounded profile/avatar caches safely.
local memory=sys.memory and sys.memory()
if not memory or memory.max<262144 then
  ui.bg(0x262724)
  ui.label(8,45,'Nearby needs Solana OS 2.0+',{size=14,color=0xFDF7DC,w=304})
  ui.label(8,81,'Use the native Settings app to update.',{size=12,color=0xFDF7DC,w=304})
  ui.label(8,114,'CANCEL returns to Solana OS.',{size=12,color=0xFDF7DC,w=304})
  ui.label(238,203,'coffer.so',{size=12,color=0xFDF7DC,w=74,align='right'})
  function on_key() return false end
  return
end
local Model,Net,T=require('model'),require('net'),require('text')
local BG,INK,DIM,PANEL,SELECTED=0x262724,0xFDF7DC,0xB0AD9C,0x30322D,0x454B3E
local state=Model.new()
local dirty,elapsed,mode=true,1000,'list'
local rows,selected,chosen,active={},1,nil,nil
local tab,scroll,showQR,qrTarget=1,0,false,1
local scanning=false
local inputOpen=false
local net=Net.new(state,function() dirty=true end)
local function label(x,y,text,size,w,color,align)
  return ui.label(x,y,T.clean(text,2048),{size=size or 12,w=w or 304,
    color=color or INK,align=align or 'left'})
end
local function rect(x,y,w,h,color,radius)
  return ui.rect(x,y,w,h,{color=color,radius=radius or 0})
end
local function avatar(e,x,y,scale)
  local s=24*(scale or 1)
  if e and e.image and type(e.image.rows)=='table' then
    local ok=pcall(ui.image,x,y,e.image.rows,{palette=e.image.palette,scale=scale or 1})
    if ok then return end
  end
  rect(x,y,s,s,0x50574A,4)
  local initial=T.chars((e and (e.name or e.handle)) or '?')[1] or '?'
  label(x,y+math.floor((s-20)/2),initial,20,s,INK,'center')
end
local function header()
  ui.bg(BG)
  pcall(ui.image,8,5,'art/coffer.png')
  label(38,3,'made by Coffer team',12,185)
  label(38,19,'yield on RWA baskets',12,210)
  label(247,3,'nearby',14,65,INK,'right')
  rect(8,36,304,1,0x494B42)
end
local function footer(text)
  rect(0,201,320,17,BG)
  label(8,203,text,12,235,DIM)
  label(238,203,'coffer.so',12,74,INK,'right')
end
local function connection()
  local info=mesh.info and mesh.info() or {}
  return info, badge.online()
end
local function displayName(e)
  if e.name and e.name~='' then return e.name end
  if e.handle then return '@'..e.handle end
  return 'Badge '..(e.id or '')
end
local function proximity(e)
  return type(e.rangeText)=='string' and e.rangeText:gsub('^Estimate: ','') or 'unknown'
end
local function profile(e,force)
  active=e;mode='profile';tab=1;scroll=0;showQR=false;qrTarget=1;dirty=true
  net:request(e,e.manual and 'x' or 'badge',force)
end
local function refresh()
  local info=mesh.info and mesh.info() or {}
  if not info.paused and not info.scanning then
    state:merge(mesh.nearby(),sys.millis(),badge.id())
  end
  rows=state:list()
  if active and not active.manual then active=state:get(active.id) or active end
  if chosen then
    for i,e in ipairs(rows) do if e.id==chosen then selected=i;break end end
  end
  selected=math.max(1,math.min(selected,#rows))
  if rows[selected] then chosen=rows[selected].id end
  for _,e in ipairs(rows) do
    if e.present and not e.loading and sys.millis()>=(e.retryAt or 0) then net:request(e) end
  end
  dirty=true
end
local function listView()
  local info,online=connection()
  local message=net.status~='' and net.status or
    (scanning and 'Scanning channels (about 57 s)' or
      (#rows..' badges  |  ch '..tostring(info.channel or '?')..(online and '  |  online' or '  |  radio')))
  label(8,39,message,12,304,DIM)
  if #rows==0 then
    label(8,75,'No badges in range yet',20,304,INK,'center')
    label(8,108,'Other badges can run any app.',12,304,DIM,'center')
    label(8,126,'They need the same mesh channel.',12,304,DIM,'center')
    label(8,151,'LEFT scan bands   RIGHT X lookup',12,304,INK,'center')
    label(8,171,'SELECT opens your linked X profile.',12,304,DIM,'center')
    footer('CANCEL exit');return
  end
  local first=math.floor((selected-1)/3)*3+1
  for pos=0,2 do
    local i=first+pos;local e=rows[i]
    if e then
      local y=55+pos*48
      rect(5,y,310,46,i==selected and SELECTED or PANEL,4)
      avatar(e,10,y+10,1)
      label(42,y+1,T.clip(displayName(e),24),14,203)
      local x=e.handle and '@'..e.handle or (e.loading and 'Matching X profile...' or 'X needs Wi-Fi')
      label(42,y+17,x,12,204,DIM)
      label(42,y+31,T.clip(e.bio~='' and e.bio or e.warning or 'SELECT for profile',36),12,266,DIM)
      local range=e.bridged and 'bridge' or (not e.present and 'lost' or
        ((info.paused or info.scanning) and 'paused' or proximity(e)))
      label(239,y+3,T.clip(range,10),12,68,INK,'right')
    end
  end
  footer('UP/DOWN  SELECT profile')
end
local function detailView()
  local e=active
  if not e then mode='list';listView();return end
  local pages={'SIGNAL','BIO','LINKS'}
  label(8,39,pages[tab]..'  '..tab..'/3'..(e.loading and '  loading...' or ''),12,304,DIM)
  if tab==1 then
    avatar(e,8,58,2)
    label(65,57,T.clip(displayName(e),28),14,247)
    label(65,77,e.handle and '@'..e.handle or 'No linked X handle',12,247,DIM)
    label(65,94,e.manual and 'X lookup: no radio distance' or (e.verified and 'Linked badge profile' or 'Waiting for badge profile'),12,247,DIM)
    local info=mesh.info and mesh.info() or {}
    local live=not e.manual and e.present and not e.bridged and not info.paused and not info.scanning
    local trend=live and (e.trend or 'STEADY') or (e.bridged and 'REMOTE BRIDGE' or (e.manual and 'X PROFILE' or 'SIGNAL PAUSED'))
    label(8,113,trend,20,196,live and 0xA9D887 or INK)
    label(204,117,live and proximity(e) or '--',14,108,INK,'right')
    local signal=live and type(e.rssi)=='number' and ('RSSI '..math.floor(e.rssi)..' dBm  |  rough estimate') or 'No current physical distance measurement'
    label(8,141,signal,12,304,DIM)
    rect(8,158,304,5,0x45493D)
    if live and type(e.smoothed)=='number' then
      local strength=math.max(0,math.min(1,(e.smoothed+95)/55))
      rect(8,158,math.max(1,math.floor(304*strength)),5,0xA9D887)
    end
    local bio=T.wrap(e.bio and e.bio~='' and e.bio or e.warning or 'RIGHT opens the full bio and website.',40)
    label(8,173,bio[1],12,304,DIM);label(8,187,bio[2] or '',12,304,DIM)
    footer('LEFT/RIGHT pages  CANCEL back')
  elseif tab==2 then
    label(8,57,T.clip(displayName(e),32),14,304)
    label(8,76,e.handle and '@'..e.handle or 'X profile',12,304,DIM)
    local text=e.bio and e.bio~='' and e.bio or e.warning or (e.loading and 'Loading public X bio...' or 'Bio unavailable. Connect Wi-Fi and refresh.')
    local lines=T.wrap(text,40)
    scroll=math.max(0,math.min(scroll,math.max(0,#lines-7)))
    for i=1,7 do label(8,92+(i-1)*14,lines[scroll+i] or '',12,304,INK) end
    footer('UP/DOWN scroll  CANCEL back')
  else
    local website=T.url(e.website)
    local xURL=e.handle and 'https://x.com/'..e.handle
    local url=qrTarget==1 and (website or xURL) or (xURL or website)
    if showQR and url and ui.qr then
      local ok=pcall(ui.qr,8,43,152,url)
      if not ok then label(8,85,'Link too long for QR',12,152) end
      label(173,71,'Scan on your phone',14,139)
      label(173,102,qrTarget==1 and website and 'Website' or 'X profile',12,139,DIM)
      label(173,133,'SELECT text / QR',12,139,DIM)
    else
      label(8,58,'Website',20,304)
      local lines=T.wrap((website or 'No public website listed.')..(xURL and ('  X profile: '..xURL) or ''),40)
      scroll=math.max(0,math.min(scroll,math.max(0,#lines-7)))
      for i=1,7 do label(8,89+(i-1)*14,lines[scroll+i] or '',12,304) end
    end
    footer(showQR and 'UP/DOWN link  SELECT text' or 'SELECT QR  CANCEL back')
  end
end
local function render()
  ui.clear();header()
  if mode=='profile' then detailView() else listView() end
  dirty=false
end
local function lookup()
  inputOpen=true
  local ok=pcall(ui.input,'Public X handle',15,function(value)
    inputOpen=false
    local h=T.handle(value)
    if h then
      local e={manual=true,handle=h,name='@'..h,bio='',present=false}
      profile(e,true)
    elseif value~=nil then ui.toast('Use letters, numbers or _ (1-15)') end
    dirty=true
  end)
  if not ok then inputOpen=false;ui.toast('Keyboard unavailable') end
end
local function ownProfile()
  local e={manual=true,name='Your X profile',bio='',present=false}
  active=e;mode='profile';tab=1;scroll=0;showQR=false;qrTarget=1
  net:request(e,'me',true);dirty=true
end
local function scan()
  if scanning then ui.toast('Scan already running');return end
  if net.current then ui.toast('Wait for profile refresh');return end
  if not mesh.scan then ui.toast('Channel scan needs Solana OS 1.1');return end
  scanning=true;dirty=true
  local ok,result,err=pcall(mesh.scan,{band='all',dwell=2600},function(channels)
    scanning=false
    local best
    for _,c in ipairs(channels or {}) do
      if type(c)=='table' and type(c.badges)=='number' and c.badges>0 and
        (not best or c.badges>best.badges) then best=c end
    end
    if best and mesh.channel then mesh.channel(best.channel);ui.toast('Listening on channel '..best.channel)
    else ui.toast('No badges heard. Try again nearby.') end
    dirty=true
  end)
  if not ok or result==nil and err then scanning=false;ui.toast('Scan unavailable');dirty=true end
end
function on_key(key,rep)
  if mode=='profile' then
    if key=='back' then mode='list';dirty=true;return true end
    if key=='left' or key=='right' then
      tab=((tab-1+(key=='right' and 1 or -1))%3)+1;scroll=0;showQR=false;dirty=true
    elseif key=='up' then
      if tab==3 and showQR then qrTarget=3-qrTarget else scroll=math.max(0,scroll-1) end;dirty=true
    elseif key=='down' then
      if tab==3 and showQR then qrTarget=3-qrTarget else scroll=scroll+1 end;dirty=true
    elseif key=='select' then
      if tab==3 then showQR=not showQR;dirty=true
      else -- refresh active profile without storing it on disk
        if active then net:request(active,active.manual and (active.handle and 'x' or 'me') or 'badge',true) end
      end
    end
    return true
  end
  if key=='back' then return false end
  if key=='up' or key=='down' then
    selected=math.max(1,math.min(#rows,selected+(key=='down' and 1 or -1)))
    if rows[selected] then chosen=rows[selected].id end
    dirty=true
  elseif key=='select' then if rows[selected] then profile(rows[selected]) else ownProfile() end
  elseif key=='right' and not rep then lookup()
  elseif key=='left' and not rep then scan() end
  return true
end
function on_tick(ms)
  elapsed=elapsed+math.max(0,math.min(ms,2000))
  if elapsed>=1000 then elapsed=elapsed%1000;refresh() end
  if not scanning then net:step() end
  if dirty and not inputOpen then render() end
end
function on_exit() net:close() end
render()
