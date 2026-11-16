-- SPDX-License-Identifier: GPL-2.0-or-later
-- Bounded first-frame GIF decoder for 24x24 public avatars. No file/network I/O.
local byte, char, sub = string.byte, string.char, string.sub
local symbols = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-'
local palette, alphabet = {}, {}
for i=0,63 do
    local symbol=sub(symbols,i+1,i+1)
    palette[symbol]=((i>>4)*85<<16)|(((i>>2)&3)*85<<8)|((i&3)*85)
end
local base64='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
for i=1,64 do alphabet[byte(base64,i)]=i-1 end

local function fail(message) error(message,0) end
local function unbase64(text)
    if #text%4~=0 then fail('Invalid base64 length') end
    local out={}
    for i=1,#text,4 do
        local a,b=alphabet[byte(text,i)],alphabet[byte(text,i+1)]
        local cc,dd=byte(text,i+2),byte(text,i+3)
        local c,d=alphabet[cc],alphabet[dd]
        if not a or not b then fail('Invalid base64') end
        if cc==61 then
            if dd~=61 or i+3~=#text or b&15~=0 then fail('Invalid base64 padding') end
            out[#out+1]=char((a<<2)|(b>>4))
        elseif dd==61 then
            if not c or i+3~=#text or c&3~=0 then fail('Invalid base64 padding') end
            out[#out+1]=char((a<<2)|(b>>4),((b&15)<<4)|(c>>2))
        else
            if not c or not d then fail('Invalid base64') end
            out[#out+1]=char((a<<2)|(b>>4),((b&15)<<4)|(c>>2),((c&3)<<6)|d)
        end
    end
    return table.concat(out)
end

local function pixels(data,minimum,limit)
    if minimum<2 or minimum>8 then fail('Invalid GIF code size') end
    local clear=1<<minimum
    local finish=clear+1
    local dict={}
    for i=0,clear-1 do dict[i]=char(i) end
    local nextCode,bits=clear+2,minimum+1
    local offset,buffer,available=1,0,0
    local previous,out,total=nil,{},0
    for _=1,2048 do
        while available<bits do
            local n=byte(data,offset)
            if not n then fail('Truncated GIF codes') end
            buffer=buffer|(n<<available)
            available,offset=available+8,offset+1
        end
        local code=buffer&((1<<bits)-1)
        buffer,available=buffer>>bits,available-bits
        if code==clear then
            nextCode,bits,previous=clear+2,minimum+1,nil
        elseif code==finish then
            if total~=limit then fail('Incomplete GIF frame') end
            return table.concat(out)
        else
            local entry
            if code<nextCode then entry=dict[code]
            elseif code==nextCode and previous then entry=previous..sub(previous,1,1) end
            if not entry then fail('Invalid GIF dictionary') end
            total=total+#entry
            if total>limit then fail('GIF frame overflow') end
            out[#out+1]=entry
            if previous and nextCode<4096 then
                dict[nextCode]=previous..sub(entry,1,1)
                nextCode=nextCode+1
                if nextCode==1<<bits and bits<12 then bits=bits+1 end
            end
            previous=entry
        end
    end
    fail('Too many GIF codes')
end

local function rawDecode(data)
    if #data>2660 then fail('Avatar too large') end
    if sub(data,1,6)~='GIF87a' and sub(data,1,6)~='GIF89a' then fail('Invalid GIF header') end
    local pos=7
    local function read()
        local n=byte(data,pos)
        if not n then fail('Truncated GIF') end
        pos=pos+1;return n
    end
    local function word() local a=read();return a|(read()<<8) end
    local function colors(count)
        local out={}
        for i=0,count-1 do
            local r,g,b=read(),read(),read()
            r,g,b=(r*3+127)//255,(g*3+127)//255,(b*3+127)//255
            local index=(r<<4)|(g<<2)|b
            out[i]=sub(symbols,index+1,index+1)
        end
        return out
    end
    local function blocks()
        local out={}
        while true do
            local n=read()
            if n==0 then return table.concat(out) end
            if pos+n-1>#data then fail('Truncated GIF block') end
            out[#out+1]=sub(data,pos,pos+n-1);pos=pos+n
        end
    end
    local width,height=word(),word()
    if width<1 or height<1 or width>24 or height>24 then fail('Avatar dimensions exceed 24x24') end
    local packed,background=read(),read();read()
    local global
    if packed&128~=0 then global=colors(1<<((packed&7)+1)) end
    local transparent
    while true do
        local marker=read()
        if marker==33 then
            local label=read()
            if label==249 then
                if read()~=4 then fail('Invalid GIF control') end
                local flags=read();word();local index=read()
                if read()~=0 then fail('Invalid GIF control') end
                if flags&1~=0 then transparent=index else transparent=nil end
            else blocks() end
        elseif marker==44 then
            local left,top,w,h=word(),word(),word(),word()
            if w<1 or h<1 or left+w>width or top+h>height then fail('Invalid GIF frame bounds') end
            local flags=read()
            local active=global
            if flags&128~=0 then active=colors(1<<((flags&7)+1)) end
            if not active then fail('Missing GIF palette') end
            local minimum=read()
            local decoded=pixels(blocks(),minimum,w*h)
            local fill=transparent and '.' or (global and global[background]) or '.'
            local canvas={}
            for i=1,width*height do canvas[i]=fill end
            local index=1
            local function row(y)
                for x=0,w-1 do
                    local color=byte(decoded,index);index=index+1
                    local symbol=active[color]
                    if not symbol then fail('Invalid GIF color') end
                    canvas[(top+y)*width+left+x+1]=color==transparent and '.' or symbol
                end
            end
            if flags&64~=0 then
                for _,pass in ipairs({{0,8},{4,8},{2,4},{1,2}}) do
                    for y=pass[1],h-1,pass[2] do row(y) end
                end
            else for y=0,h-1 do row(y) end end
            local rows={}
            for y=0,height-1 do rows[y+1]=table.concat(canvas,'',y*width+1,(y+1)*width) end
            return {rows=rows,palette=palette,w=width,h=height}
        elseif marker==59 then fail('GIF has no frame')
        else fail('Invalid GIF block') end
    end
end

local function decode(text)
    if type(text)~='string' or #text>3584 then return nil,'Avatar too large' end
    local ok,result=pcall(function()
        if sub(text,1,22)=='data:image/gif;base64,' then text=unbase64(sub(text,23)) end
        return rawDecode(text)
    end)
    if ok then return result end
    return nil,result
end

return {decode=decode}
