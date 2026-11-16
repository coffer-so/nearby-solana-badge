-- SPDX-License-Identifier: MIT
package.path=assert(arg[1])..'/?.lua;'..package.path
local T=require('text');local n=0
local function check(v)n=n+1;assert(v)end
check(T.handle('@sample_user')=='sample_user')
for _,s in ipairs({'','../../bad','bad handle','https://x.com/a',string.rep('a',16)})do check(T.handle(s)==nil)end
check(T.url('javascript:alert(1)')==nil)
check(T.url('https://example.com')=='https://example.com')
check(T.clean(nil)=='')
check(T.clean('a\0b\n c')=='a b c')
local s='Привет 世界 🪙 '..string.rep('longword',20)
for width=1,40 do
 for _,line in ipairs(T.wrap(s,width))do check((utf8.len(line)or 999)<=width)end
 check(utf8.len(T.clip(s,width))~=nil)
end
check(utf8.len(T.clean('🪙',3))~=nil)
check(T.clean('a\255b')=='a')
print('text_spec: '..n..' UTF8/handle/link/layout checks')
