-- SPDX-License-Identifier: GPL-2.0-or-later
-- Public profile metadata and optional thumbnail; no API keys or persistence.
local GIF=require('gif')
local cache,order={},{}
local function now() return sys and sys.millis and sys.millis() or 0 end
local function bounded(value,n)
    if type(value)~='string' then return '' end
    value=value:gsub('[%z\1-\8\11\12\14-\31\127]','')
    if #value>n then
        value=value:sub(1,n)
        -- Avoid a partial UTF-8 character at the field boundary.
        local ok=utf8.len(value)
        while not ok and #value>0 do value=value:sub(1,-2);ok=utf8.len(value) end
    end
    return value
end
local function avatarURL(url)
    if type(url)~='string' or #url>300 or url:find('[%z\1-\32\127]') then return nil end
    if url:match('^https://pbs%.twimg%.com/profile_images/[%w%p]+$')
        or url:match('^https://abs%.twimg%.com/sticky/default_profile_images/[%w%p]+$') then
        return url
    end
end
local function transport(url,accept,cb)
    if not http or type(http.get)~='function' then cb(false,'HTTP unavailable');return end
    local done=false
    local function once(ok,data,status)
        if done then return end
        done=true;cb(ok,data,status)
    end
    local ok=pcall(http.get,url,{Accept=accept},function(success,res)
        if not success then once(false,bounded(res,80));return end
        if type(res)~='table' or type(res.body)~='string' then once(false,'Invalid service response');return end
        if res.status~=200 then
            local why=res.status==404 and 'X profile not found'
                or res.status==429 and 'Service rate limited' or 'Service HTTP '..tostring(res.status)
            once(false,why,res.status);return
        end
        if res.truncated or #res.body>3584 then once(false,'Response exceeds badge limit');return end
        once(true,res.body)
    end)
    if not ok then once(false,'Request unavailable') end
end
local function fetch(handle,cb,force)
    if type(handle)~='string' then cb(false,'Invalid X handle');return end
    handle=handle:gsub('^@',''):lower()
    if #handle<1 or #handle>15 or not handle:match('^[a-z0-9_]+$') then cb(false,'Invalid X handle');return end
    local entry=cache[handle]
    local time=now()
    if not force and entry and time-entry.time>=0 and time-entry.time<300000 then cb(true,entry.value);return end
    local function unsupported(status) return status==404 or status==405 or status==501 end
    -- FxEmbed retains a separate legacy profile handler. Some public API edges
    -- return 404 for v2 while this route succeeds; retry it at most once.
    local function attempt(legacy)
        local url='https://api.fxtwitter.com/'..(legacy and '' or '2/profile/')..handle
            ..(legacy and '' or '?about_account=0')
        transport(url,'application/json',function(ok,body,status)
            if not ok then
                if not legacy and unsupported(status) then attempt(true) else cb(false,body) end
                return
            end
            local valid,payload=pcall(json.decode,body)
            if valid and type(payload)=='table' and unsupported(payload.code) then
                if not legacy then attempt(true) else cb(false,payload.code==404 and 'X profile not found' or 'Profile route unavailable') end
                return
            end
            local user=valid and type(payload)=='table' and payload.user
            if type(user)~='table' or payload.code~=200 or type(user.name)~='string' then
                cb(false,'Invalid profile response');return
            end
            if user.screen_name~=nil and (type(user.screen_name)~='string' or user.screen_name:lower()~=handle) then
                cb(false,'Profile handle mismatch');return
            end
            local website=type(user.website)=='table' and user.website.url or ''
            local value={handle=handle,name=bounded(user.name,80),bio=bounded(user.description,640),
                website=bounded(website,256),url='https://x.com/'..handle,avatarURL=avatarURL(user.avatar_url),source='FxTwitter'}
            if not cache[handle] then order[#order+1]=handle end
            cache[handle]={value=value,time=now()}
            if #order>8 then cache[table.remove(order,1)]=nil end
            cb(true,value)
        end)
    end
    attempt(false)
end
local function avatar(url,cb)
    url=avatarURL(url)
    if not url then cb(false,'Avatar unavailable');return end
    local encoded=url:gsub('[^A-Za-z0-9%-._~]',function(c)return ('%%%02X'):format(string.byte(c)) end)
    local request='https://wsrv.nl/?url='..encoded..'&w=24&h=24&fit=cover&output=gif&encoding=base64&n=1'
    if #request>512 then cb(false,'Avatar URL too long');return end
    transport(request,'text/plain',function(ok,body)
        if not ok then cb(false,body);return end
        local image,why=GIF.decode(body)
        if image then cb(true,image) else cb(false,why or 'Avatar unavailable') end
    end)
end
return {fetch=fetch,avatar=avatar}
