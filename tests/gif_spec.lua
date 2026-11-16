-- SPDX-License-Identifier: GPL-2.0-or-later
-- Synthetic indexed gradients, generated with Pillow; no personal avatars.
local root=arg[1] or "app"
package.path=root.."/?.lua;"..package.path
local GIF=require("gif")
local count,peak=0,0
local function check(ok,why) count=count+1;assert(ok,why) end
local function decode(data)
    local instructions=0
    debug.sethook(function()instructions=instructions+100 end,'',100)
    local image,why=GIF.decode(data)
    debug.sethook()
    peak=math.max(peak,instructions)
    check(instructions<200000,'decoder exceeds callback VM budget')
    return image,why
end
local fixtures={
interlaced="data:image/gif;base64,R0lGODdhGAAYAIcAAAAAAAE1YQJqwgOfIwTUhAUJ5QY+RgdzpwioCAndaQoSygtHKwx8jA2x7Q7mTg8brxBQEBGFcRK60hPvMxQklBVZ9RaOVhfDtxj4GBkteRpi2huXOxzMnB0B/R42Xh9rvyCgICHVgSIK4iM/QyR0pCWpBSbeZicTxyhIKCl9iSqy6ivnSywcrC1RDS6Gbi+7zzDwMDElkTJa8jOPUzTEtDX5FTYudjdj1ziYODnNmToC+js3WzxsvD2hHT7Wfj8L30BAQEF1oUKqAkPfY0QUxEVJJUZ+hkez50joSEkdqUpSCkuHa0y8zE3xLU4mjk9b71CQUFHFsVL6ElMvc1Rk1FWZNVbOllcD91g4WFltuVqiGlvXe1wM3F1BPV52nl+r/2DgYGEVwWJKImN/g2S05GXpRWYepmdTB2iIaGm9yWryKmsni2xc7G2RTW7Grm/7D3AwcHFl0XKaMnPPk3QE9HU5VXZutnejF3jYeHkN2XpCOnt3m3ys/H3hXX4Wvn9LH4CAgIG14YLqQoMfo4RUBIWJZYa+xofzJ4goiIld6YqSSovHq4z8DI0xbY5mzo+bL5DQkJEF8ZI6UpNvs5SkFJXZdZYO1pdDN5h4mJmt+ZriWpsXu5xMHJ2BfZ623p/rP6AgoKFVAaKKYqO/w6T0JKUphaZe5qeTR6jIqKn9Caoyaqtny6ycLK3Rja4G7q87T7BwsLGlEbLacrMP07RENLV5lbau9rfjV7gYuLlNGbqCeru327zsPL0hnb5W/r+LX8DAwMH1IcIqgsNf48SURMXJpcb+BsczZ8hoyMmdKcrSissH68w8TM1xrc6mDs/bb9AQ0NFFMdJ6ktOv89TkVNUZtdZOFteDd9i42NntOdoimttX+9yMXN3Bvd72Ht8rf+Bg4OGVQeLKouP/A+Q0ZOVpxeaeJufTh+gI6Ok9SepyquunC+zcbO0Rze5GLu97j/Cw8PHlUfIasvNPE/SEdPW51fbuNvcjl/hY+PmNWfrCuvv3G/wsfP1h3f6WPv/LnywAAAAAGAAYAEAI/wABRBAxg0gVM3cQZVK1i1k3d/8ghJAxhEoZO4dQBNECJs8fTLFuQbP2rp6DEy2MMCmzhlCnUbygxPnTaFOqW9jM0RMAwcOPJlvS3Ck0iZYwaN4opfI1DZ26fxRS+ABSRc0fSpZWAat2jV0ACyt4ZRsHQAGFGDuKiGGTaFInXcScrav3j4OJIU3I2UOggYUPKGLoGMKkipczcPIIWEBxIseSLm+UdIEzyFIqXs/E1auHYIOLIFTO6GnUCNQsY9m81WMw4oSPKlngHFokKlcvauveGegQAscTM2rkNKoEC9e0bfb8ZQjBg8iXM4IUlWpVCxq2efsMlIjRgwsaOoA+rf+6NUycO33auSf5Hl5Tr2bd2vVr0KFFjyZd2vRp1KnV+24AQAACDC4IYYUafkhiyim7PDPOPQswAAINSHABRxyFZNJKMCXckMQWbfwRySi1HJPNOv08EMIMRVyRBhp6MOIJLG8Mcskqv0xzDjr8QEACDkw0EUYdiXQSiyzGaOOOALk8U84+/lCgAhBDZPFGIYh4QosyzYyTDz8SoOBDEANsMAMOUKDRRiGdiKLLL9e8Qw8DJKQQhBFe2LHHJE2cEQgioqQyjDLkrFMAAya0cIQTaLyRCCSqELNMOZfMwgs24fRjwAMr0ABFFnX4ccgorCATjTb2/LMBCeH8o0AFM/ilkMQZcvSxiSmxPKNNOQM4kAEJQjSBhR0rLIFFGXJI8gkruRhjzjwANKCBDkdQEYYbjmyCSi11XGJKLcRMI048ADwQAxBPeNEGH4tokgou2qSDzwG/QBOOPANQUIINR2CRhh6LcNKKL8+AE48AE5BQgxEJcPCCEFWgsYcjodBCyzHatAPABCbkwAQTX8hRCCZToNGHJKcs1VQ/UEk1RVVXZbWVOgEBADs=",
localPalette="data:image/gif;base64,R0lGODdhGAAYAAcAACwAAAAAGAAYAMcAAAABNWECasIDnyME1IQFCeUGPkYHc6cIqAgJ3WkKEsoLRysMfIwNse0O5k4PG68QUBARhXESutIT7zMUJJQVWfUWjlYXw7cY+BgZLXkaYtoblzsczJwdAf0eNl4fa78goCAh1YEiCuIjP0MkdKQlqQUm3mYnE8coSCgpfYkqsuor50ssHKwtUQ0uhm4vu88w8DAxJZEyWvIzj1M0xLQ1+RU2LnY3Y9c4mDg5zZk6Avo7N1s8bLw9oR0+1n4/C99AQEBBdaFCqgJD32NEFMRFSSVGfoZHs+dI6EhJHalKUgpLh2tMvMxN8S1OJo5PW+9QkFBRxbFS+hJTL3NUZNRVmTVWzpZXA/dYOFhZbblaohpb13tcDNxdQT1edp5fq/9g4GBhFcFiSiJjf4NktORl6UVmHqZnUwdoiGhpvclq8iprJ4tsXOxtkU1uxq5v+w9wMHBxZdFymjJzz5N0BPR1OVV2brZ3oxd42Hh5Ddl6Qjp7d5t8rPx94V1+Fr5/Sx+AgICBteGC6kKDH6OEVASFiWWGvsaH8yeIKIiJXemKkkqLx6uM/AyNMW2OZs6Pmy+Q0JCRBfGSOlKTb7OUpBSV2XWWDtaXQzeYeJiZrfma4lqbF7ucTBydgX2ett6f6z+gIKChVQGiimKjv8Ok9CSlKYWmXuank0eoyKip/QmqMmqrZ8usnCyt0Y2uBu6vO0+wcLCxpRGy2nKzD9O0RDS1eZW2rva341e4GLi5TRm6gnq7t9u87Dy9IZ2+Vv6/i1/AwMDB9SHCKoLDX+PElETFyaXG/gbHM2fIaMjJnSnK0orLB+vMPEzNca3Opg7P22/QENDRRTHSepLTr/PU5FTVGbXWThbXg3fYuNjZ7TnaIprbV/vcjFzdwb3e9h7fK3/gYODhlUHiyqLj/wPkNGTlacXmnibn04foCOjpPUnqcqrrpwvs3GztEc3uRi7ve4/wsPDx5VHyGrLzTxP0hHT1udX27jb3I5f4WPj5jVn6wrr79xv8LHz9Yd3+lj7/y58I/wABRBAxg0gVM3cQZVK1i1k3d/8ghJAxhEoZO4dQBNECJs8fTLFuQbP2rp6DEy2MMCmzhlCnUbygxPnTaFOqW9jM0RMAwcOPJlvS3Ck0iZYwaN4opfI1DZ26fxRS+ABSRc0fSpZWAat2jV0ACyt4ZRsHQAGFGDuKiGGTaFInXcScrav3j4OJIU3I2UOggYUPKGLoGMKkipczcPIIWEBxIseSLm+UdIEzyFIqXs/E1auHYIOLIFTO6GnUCNQsY9m81WMw4oSPKlngHFokKlcvauveGegQAscTM2rkNKoEC9e0bfb8ZQjBg8iXM4IUlWpVCxq2efsMlIjRgwsaOoA+rf+6NUycO33auSf5Hl5Tr2bd2vVr0KFFjyZd2vRp1KnV+24AQAACDC4IYYUafkhiyim7PDPOPQswAAINSHABRxyFZNJKMCXckMQWbfwRySi1HJPNOv08EMIMRVyRBhp6MOIJLG8Mcskqv0xzDjr8QEACDkw0EUYdiXQSiyzGaOOOALk8U84+/lCgAhBDZPFGIYh4QosyzYyTDz8SoOBDEANsMAMOUKDRRiGdiKLLL9e8Qw8DJKQQhBFe2LHHJE2cEQgioqQyjDLkrFMAAya0cIQTaLyRCCSqELNMOZfMwgs24fRjwAMr0ABFFnX4ccgorCATjTb2/LMBCeH8o0AFM/ilkMQZcvSxiSmxPKNNOQM4kAEJQjSBhR0rLIFFGXJI8gkruRhjzjwANKCBDkdQEYYbjmyCSi11XGJKLcRMI048ADwQAxBPeNEGH4tokgou2qSDzwG/QBOOPANQUIINR2CRhh6LcNKKL8+AE48AE5BQgxEJcPCCEFWgsYcjodBCyzHatAPABCbkwAQTX8hRCCZToNGHJKcs1VQ/UEk1RVVXZbWVOgEBADs=",
transparent="data:image/gif;base64,R0lGODlhCAAIAIcAAAAAAAE1YQJqwgOfIwTUhAUJ5QY+RgdzpwioCAndaQoSygtHKwx8jA2x7Q7mTg8brxBQEBGFcRK60hPvMxQklBVZ9RaOVhfDtxj4GBkteRpi2huXOxzMnB0B/R42Xh9rvyCgICHVgSIK4iM/QyR0pCWpBSbeZicTxyhIKCl9iSqy6ivnSywcrC1RDS6Gbi+7zzDwMDElkTJa8jOPUzTEtDX5FTYudjdj1ziYODnNmToC+js3WzxsvD2hHT7Wfj8L30BAQEF1oUKqAkPfY0QUxEVJJUZ+hkez50joSEkdqUpSCkuHa0y8zE3xLU4mjk9b71CQUFHFsVL6ElMvc1Rk1FWZNVbOllcD91g4WFltuVqiGlvXe1wM3F1BPV52nl+r/2DgYGEVwWJKImN/g2S05GXpRWYepmdTB2iIaGm9yWryKmsni2xc7G2RTW7Grm/7D3AwcHFl0XKaMnPPk3QE9HU5VXZutnejF3jYeHkN2XpCOnt3m3ys/H3hXX4Wvn9LH4CAgIG14YLqQoMfo4RUBIWJZYa+xofzJ4goiIld6YqSSovHq4z8DI0xbY5mzo+bL5DQkJEF8ZI6UpNvs5SkFJXZdZYO1pdDN5h4mJmt+ZriWpsXu5xMHJ2BfZ623p/rP6AgoKFVAaKKYqO/w6T0JKUphaZe5qeTR6jIqKn9Caoyaqtny6ycLK3Rja4G7q87T7BwsLGlEbLacrMP07RENLV5lbau9rfjV7gYuLlNGbqCeru327zsPL0hnb5W/r+LX8DAwMH1IcIqgsNf48SURMXJpcb+BsczZ8hoyMmdKcrSissH68w8TM1xrc6mDs/bb9AQ0NFFMdJ6ktOv89TkVNUZtdZOFteDd9i42NntOdoimttX+9yMXN3Bvd72Ht8rf+Bg4OGVQeLKouP/A+Q0ZOVpxeaeJufTh+gI6Ok9SepyquunC+zcbO0Rze5GLu97j/Cw8PHlUfIasvNPE/SEdPW51fbuNvcjl/hY+PmNWfrCuvv3G/wsfP1h3f6WPv/LnyH5BAEAAAAALAAAAAAIAAgAAAgaAAFUqSKQ4ECDCBEWBLBwYEGFBxsSlPhQYkAAOw==",
}
local gradient=assert(decode(fixtures.interlaced))
check(gradient.w==24 and gradient.h==24 and #gradient.rows==24,'gradient dimensions')
local colors=0
for key in pairs(gradient.palette) do
    check(#key==1 and key:byte()>=33 and key:byte()<=126 and key~='.' and key~=' ',
        'palette keys must be printable single-byte characters')
    colors=colors+1
end
check(colors==64,'avatar palette is bounded to 64 RGB222 colors')
for y=0,23 do for x=0,23 do
    local i=(x*17+y*37+(x*y)%19)%256
    local r,g,b=i,(i*53)%256,(i*97)%256
    r,g,b=((r*3+127)//255)*85,((g*3+127)//255)*85,((b*3+127)//255)*85
    local key=gradient.rows[y+1]:sub(x+1,x+1)
    check(gradient.palette[key]==((r<<16)|(g<<8)|b),'interlaced LZW gradient pixel mismatch')
end end
local localImage=assert(decode(fixtures.localPalette))
for y=1,24 do check(localImage.rows[y]==gradient.rows[y],'local/global palettes decode identically') end
local transparent=assert(decode(fixtures.transparent))
for y=0,7 do for x=0,7 do
    local key=transparent.rows[y+1]:sub(x+1,x+1)
    check((key=='.')==((x+y)%3==0),'GIF transparency preserves only transparent pixels')
end end
local function word(n)return string.char(n&255,n>>8) end
local function fixed(codes)
    local out,buffer,bits={},0,0
    for _,code in ipairs(codes) do
        buffer=buffer|(code<<bits);bits=bits+3
        while bits>=8 do out[#out+1]=string.char(buffer&255);buffer=buffer>>8;bits=bits-8 end
    end
    if bits>0 then out[#out+1]=string.char(buffer) end
    return table.concat(out)
end
local function frame(w,h,left,top,fw,fh,codes)
    local chunks={}
    for i=1,#codes,255 do
        local part=codes:sub(i,i+254);chunks[#chunks+1]=string.char(#part)..part
    end
    return 'GIF89a'..word(w)..word(h)..string.char(128,0,0,0,0,0,255,255,255)..','
        ..word(left)..word(top)..word(fw)..word(fh)..string.char(0,2)..table.concat(chunks)..string.char(0)..';'
end
local offset=assert(decode(frame(5,5,2,3,1,1,fixed({4,1,5}))))
for y=1,5 do for x=1,5 do
    local color=offset.palette[offset.rows[y]:sub(x,x)]
    check(color==((x==3 and y==4) and 0xFFFFFF or 0),'subframe offset/background composition')
end end
local complete=frame(1,1,0,0,1,1,fixed({4,1,5}))
for i=1,#complete-2 do
    local image,why=decode(complete:sub(1,i))
    check(not image and type(why)=='string','truncated header, palette, frame or blocks must fail')
end
for _,bad in ipairs({'','not a gif','data:image/gif;base64,A===','data:image/gif;base64,AAAA=',
    string.rep('x',3585),frame(25,1,0,0,1,1,fixed({4,1,5})),
    frame(2,2,2,0,1,1,fixed({4,1,5})),frame(1,1,0,0,1,1,fixed({4,0,1,5})),
    frame(1,1,0,0,1,1,fixed({4,7,5})),frame(2,1,0,0,2,1,fixed({4,0,5}))}) do
    local image,why=decode(bad)
    check(not image and type(why)=='string','malformed GIF must return a bounded error')
end
local storm={}
for i=1,2500 do storm[i]=4 end
storm[#storm+1]=5
local image,why=decode(frame(1,1,0,0,1,1,fixed(storm)))
check(not image and why=='Too many GIF codes','clear-code storms terminate within bounded VM')
print('gif_spec: '..count..' checks passed; peak '..peak..'/200000 VM')
