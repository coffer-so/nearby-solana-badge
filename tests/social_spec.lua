-- SPDX-License-Identifier: GPL-2.0-or-later
-- Synthetic profile/HTTP fixtures only; never contact live social accounts.
local root=arg[1] or 'app'
package.path=root..'/?.lua;'..package.path
local pending,clock,calls={},0,0
local checks=0
local function check(ok,why) checks=checks+1;assert(ok,why) end
local payload
json={decode=function(body)
    if body=='throws' then error('synthetic decoder failure') end
    if body~='fixture' then return nil,'invalid JSON' end
    return payload
end}
http={get=function(url,headers,cb)
    calls=calls+1
    check(#url<=512 and url:match('^https://'),'request fits badge HTTPS URL contract')
    check(headers['User-Agent']==nil,'badge owns User-Agent header')
    pending[#pending+1]={url=url,headers=headers,cb=cb}
end}
sys={millis=function()return clock end}
local social=require('social')
local function profile()
    return {code=200,user={name='Synthetic User',screen_name='example_user',
        description='A synthetic biography.\nNo real profile data.',
        website={url='https://example.test/project'},url='https://x.com/example_user',
        avatar_url='https://pbs.twimg.com/profile_images/1/synthetic_normal.png'}}
end
local function response(ok,res)
    local request=table.remove(pending,1)
    check(request~=nil,'one pending request expected')
    request.cb(ok,res)
    return request
end
local function good()
    payload=profile()
    payload.user.screen_name=pending[1].url:gsub('%?.*$',''):match('/([a-z0-9_]+)$')
    return response(true,{status=200,body='fixture',type='application/json',truncated=false})
end
local ok,result,count
local function receive(a,b) ok,result,count=a,b,(count or 0)+1 end
payload=profile();count=0
social.fetch('@Example_User',receive)
check(count==0 and #pending==1,'metadata request is asynchronous')
check(pending[1].url=='https://api.fxtwitter.com/2/profile/example_user?about_account=0',
    'documented profile endpoint excludes unnecessary about-account fields')
good()
check(ok and count==1 and result.handle=='example_user' and result.name=='Synthetic User','profile shape normalized')
check(result.bio==payload.user.description and result.website=='https://example.test/project','bio and website extracted')
check(result.avatarURL==payload.user.avatar_url and result.url=='https://x.com/example_user','public avatar and canonical profile URL')
check(result.id==nil and result.followers==nil and result.source=='FxTwitter','unneeded account fields excluded')
local before=calls
social.fetch('EXAMPLE_USER',receive)
check(ok and calls==before and count==2,'short RAM cache avoids duplicate service calls')
social.fetch('EXAMPLE_USER',receive,true)
check(calls==before+1 and #pending==1,'explicit refresh bypasses metadata cache')
good()
clock=300001
social.fetch('example_user',receive)
check(#pending==1,'expired metadata is refreshed')
good()

for _,handle in ipairs({'','@@name','bad/name','bad name','https://x.com/x',string.rep('a',16)}) do
    before=calls;social.fetch(handle,receive)
    check(not ok and result=='Invalid X handle' and calls==before,'invalid handle cannot construct a request')
end
local failures={
    {false,'offline'}, {false,'not linked'},
    {true,{status=429,body='{}'}},
    {true,{status=503,body='{}'}},{true,{status=302,body='redirect'}},
    {true,{status=200,body='fixture',truncated=true}},
    {true,{status=200,body=string.rep('x',3585)}},
    {true,{status=200,body='bad JSON'}},{true,{status=200,body='throws'}},
    {true,{status=200,body='fixture'}},{true,{status=200}},
}
for i,f in ipairs(failures) do
    payload={code=500,user=nil}
    local prior=count
    social.fetch('failure'..i,receive)
    local request=response(f[1],f[2])
    check(not ok and type(result)=='string' and count==prior+1,'service errors produce one bounded callback')
    request.cb(f[1],f[2])
    check(count==prior+1,'duplicate service callback is ignored')
end
for _,status in ipairs({404,405,501}) do
    local prior=count
    local handle='legacy'..status
    social.fetch(handle,receive)
    local first=response(true,{status=status,body='{}'})
    check(count==prior and #pending==1,'unsupported v2 response queues one fallback without final callback')
    check(pending[1].url=='https://api.fxtwitter.com/'..handle,'legacy fallback stays on same allowed host')
    good()
    check(ok and result.handle==handle and count==prior+1,'legacy result has same normalized metadata contract')
    first.cb(true,{status=status,body='{}'})
    check(count==prior+1 and #pending==0,'duplicate v2 response cannot schedule extra fallback')
end
local prior=count
social.fetch('missing_user',receive)
response(true,{status=404,body='{}'})
response(true,{status=404,body='{}'})
check(not ok and result=='X profile not found' and count==prior+1 and #pending==0,
    'missing account stops after exactly two requests and one final callback')
social.fetch('jsonfallback',receive)
payload={code=404}
response(true,{status=200,body='fixture'})
check(#pending==1,'JSON error code also supports legacy fallback')
payload=profile();payload.user.screen_name='wrong_user'
response(true,{status=200,body='fixture'})
check(not ok and result=='Profile handle mismatch','legacy fallback still rejects wrong returned identity')
social.fetch('bounded',receive)
payload=profile();payload.user.name=string.rep('Ж',41)..'\0'
payload.user.screen_name='bounded'
payload.user.description=string.rep('☀',300)
payload.user.website='invalid shape';payload.user.avatar_url='https://private.invalid/photo'
response(true,{status=200,body='fixture'})
check(ok and #result.name<=80 and utf8.len(result.name)~=nil and not result.name:find('\0',1,true),'name bounded on UTF-8 boundary')
check(#result.bio<=640 and utf8.len(result.bio)~=nil,'biography bounded on UTF-8 boundary')
check(result.website=='' and result.avatarURL==nil,'missing/unsupported optional fields preserve metadata success')
social.fetch('matchcase',receive)
payload=profile();payload.user.screen_name='someone_else'
response(true,{status=200,body='fixture'})
check(not ok and result=='Profile handle mismatch','wrong returned account cannot be shown or cached')
social.fetch('matchcase',receive)
payload=profile();payload.user.screen_name='MATCHCASE'
response(true,{status=200,body='fixture'})
check(ok and result.handle=='matchcase','returned account comparison is case-insensitive')
social.fetch('optional',receive)
payload=profile();payload.user.screen_name=nil
response(true,{status=200,body='fixture'})
check(ok and result.handle=='optional','missing optional screen name preserves requested identity')
for i=1,9 do social.fetch('cache'..i,receive);good() end
social.fetch('cache1',receive)
check(#pending==1,'metadata cache evicts older entries beyond eight')
good()

local tiny='data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACwAAAAAAQABAAACAkQBADs='
local url='https://pbs.twimg.com/profile_images/1/synthetic_normal.png'
social.avatar(url,receive)
local request=pending[1]
check(request.url:match('^https://wsrv%.nl/%?url=https%%3A%%2F%%2Fpbs%.twimg%.com%%2F'),
    'avatar conversion uses only explicit wsrv host with escaped source')
check(request.url:find('&w=24&h=24&fit=cover&output=gif&encoding=base64&n=1',1,true)~=nil,
    'avatar conversion requests one bounded ASCII GIF frame')
response(true,{status=200,body=tiny,type='text/plain'})
check(ok and result.w==1 and result.h==1 and #result.rows==1 and type(result.palette)=='table',
    'avatar callback returns native row/palette image data')
for _,bad in ipairs({'https://example.test/a.png','http://pbs.twimg.com/profile_images/a.png',
    'https://pbs.twimg.com.evil.test/profile_images/a.png','https://pbs.twimg.com:443/profile_images/a.png',
    'https://user@pbs.twimg.com/profile_images/a.png','https://pbs.twimg.com/profile_images/with space.png'}) do
    before=calls;social.avatar(bad,receive)
    check(not ok and calls==before,'unsupported avatar URL never reaches proxy')
end
before=calls
social.avatar('https://pbs.twimg.com/profile_images/'..string.rep('%',240),receive)
check(not ok and result=='Avatar URL too long' and calls==before,'escaped thumbnail URL still obeys 512-byte badge limit')
social.avatar(url,receive);response(true,{status=200,body=tiny,truncated=true})
check(not ok,'truncated avatar is never decoded')
social.avatar(url,receive);response(true,{status=200,body='not a GIF'})
check(not ok and type(result)=='string','broken thumbnail preserves graceful fallback')
social.avatar('https://abs.twimg.com/sticky/default_profile_images/synthetic.png',receive)
check(#pending==1,'default X avatar host is supported through same proxy')
response(false,'timeout')
check(not ok and result=='timeout','avatar timeout is exposed without private response contents')
print('social_spec: '..checks..' checks passed; synthetic HTTP, cache, bounds, errors and avatar conversion')
