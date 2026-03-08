if not skey then
    return print("skey not found!")
end

do
    local bit = bit32
    local byte = string.byte
    local char = string.char
    local rep = string.rep
    local len = string.len
    local format = string.format
    local concat = table.concat

    if type(gethwid) ~= "function" then
        return
    end

    local message = gethwid()

    -- convert secret hex to key
    local s1="3b66bf61c557262a"
    local s2="c490aa6a8db0142b"
    local s3="8546dab39ff14ce8"
    local s4="e6666f9f0458ced8"
    local secret_hex = s1..s2..s3..s4
    local key_bytes = {}
    for i=1,#secret_hex,2 do
        key_bytes[#key_bytes+1] = char(tonumber(secret_hex:sub(i,i+1),16))
    end
    local key = concat(key_bytes)
    local base_key = key

    -- SHA256 constants
    local K={
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,
        0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,
        0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,
        0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,
        0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,
        0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,
        0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,
        0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,
        0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
    }

    -- SHA256 function
    local function sha256(msg)
        local H={0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
                 0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
        local ml=len(msg)*8
        msg=msg..char(0x80)
        while (len(msg)%64)~=56 do msg=msg.."\0" end
        msg=msg..char(0,0,0,0,
            bit.band(bit.rshift(ml,24),255),
            bit.band(bit.rshift(ml,16),255),
            bit.band(bit.rshift(ml,8),255),
            bit.band(ml,255)
        )
        for i=1,len(msg),64 do
            local w={}
            for j=0,15 do
                local a,b,c,d=byte(msg,i+j*4,i+j*4+3)
                w[j]=bit.lshift(a,24)+bit.lshift(b,16)+bit.lshift(c,8)+d
            end
            for j=16,63 do
                local s0=bit.bxor(bit.rrotate(w[j-15],7),bit.rrotate(w[j-15],18),bit.rshift(w[j-15],3))
                local s1=bit.bxor(bit.rrotate(w[j-2],17),bit.rrotate(w[j-2],19),bit.rshift(w[j-2],10))
                w[j]=bit.band(w[j-16]+s0+w[j-7]+s1,0xffffffff)
            end
            local a,b,c,d,e,f,g,h=table.unpack(H)
            for j=0,63 do
                local S1=bit.bxor(bit.rrotate(e,6),bit.rrotate(e,11),bit.rrotate(e,25))
                local ch=bit.bxor(bit.band(e,f),bit.band(bit.bnot(e),g))
                local temp1=bit.band(h+S1+ch+K[j+1]+w[j],0xffffffff)
                local S0=bit.bxor(bit.rrotate(a,2),bit.rrotate(a,13),bit.rrotate(a,22))
                local maj=bit.bxor(bit.band(a,b),bit.band(a,c),bit.band(b,c))
                local temp2=bit.band(S0+maj,0xffffffff)
                h,g,f,e,d,c,b,a=g,f,e,bit.band(d+temp1,0xffffffff),c,b,a,bit.band(temp1+temp2,0xffffffff)
            end
            for j=1,8 do H[j]=bit.band(H[j]+({a,b,c,d,e,f,g,h})[j],0xffffffff) end
        end
        local out={}
        for i=1,8 do
            local v=H[i]
            out[#out+1]=char(
                bit.band(bit.rshift(v,24),255),
                bit.band(bit.rshift(v,16),255),
                bit.band(bit.rshift(v,8),255),
                bit.band(v,255)
            )
        end
        return concat(out)
    end

    -- prepare HMAC
    local block=64
    if #key>block then key=sha256(key) end
    if #key<block then key=key..rep("\0",block-#key) end
    local ipad, opad = {}, {}
    for i=1,block do
        local k=byte(key,i)
        ipad[i]=char(bit.bxor(k,0x36))
        opad[i]=char(bit.bxor(k,0x5c))
    end

    local inner=sha256(concat(ipad)..message)
    local final=sha256(concat(opad)..inner)
    local hex=final:gsub(".",function(c) return format("%02x",byte(c)) end)

    local msg = skey.."|"..hex
    local inner2=sha256(concat(ipad)..msg)
    local final2=sha256(concat(opad)..inner2)
    local signed=final2:gsub(".",function(c) return format("%02x",byte(c)) end)

    local HttpRequest = http_request or request or (http and http.request)
    if not HttpRequest then
        error("Couldn't request api in this environment!")
    end
    local HttpService=game:GetService("HttpService")

    local URL1="https://64e9-2a09-bac6-d841-2696-00-3d8-55.ngrok-free.app/check/1"
    local Response=HttpRequest({
        Url=URL1,
        Method="POST",
        Headers={["Content-Type"]="application/json"},
        Body=string.format('{"a":"%s","b":"%s","c":"%s"}',skey,hex,signed)
    })
    -- print(Response.Body) debug stuff
    local data = HttpService:JSONDecode(Response.Body)
    if data.error then return loadstring(data.error)() end

    local real_session=nil
    for _,entry in ipairs(data.responses) do
        local session,sig = entry.a, entry.b
        local k=base_key
        if #k>64 then k=sha256(k) end
        if #k<64 then k=k..rep("\0",64-#k) end
        local ipad2, opad2 = {}, {}
        for i=1,64 do
            local b=byte(k,i)
            ipad2[i]=char(bit.bxor(b,0x36))
            opad2[i]=char(bit.bxor(b,0x5c))
        end
        local hmac_inner=sha256(concat(ipad2)..session)
        local hmac_final=sha256(concat(opad2)..hmac_inner)
        local session_hmac=hmac_final:gsub(".",function(c) return format("%02x",byte(c)) end)
        if session_hmac==sig then
            real_session=session
            -- print(real_session) debug stuff
            break
        end
    end

    signed=nil
    if real_session then
        local msg2=real_session.."|"..hex
        local k=base_key
        if #k>64 then k=sha256(k) end
        if #k<64 then k=k..rep("\0",64-#k) end
        local ipad2, opad2 = {}, {}
        for i=1,64 do
            local b=byte(k,i)
            ipad2[i]=char(bit.bxor(b,0x36))
            opad2[i]=char(bit.bxor(b,0x5c))
        end
        local inner3=sha256(concat(ipad2)..msg2)
        local final3=sha256(concat(opad2)..inner3)
        signed=final3:gsub(".",function(c) return format("%02x",byte(c)) end)
    end

    local URL2="https://64e9-2a09-bac6-d841-2696-00-3d8-55.ngrok-free.app/check/2"
    Response=HttpRequest({
        Url=URL2,
        Method="POST",
        Headers={["Content-Type"]="application/json"},
        Body=string.format('{"key":"%s","sig":"%s"}',skey,signed)
    })
    loadstring(Response.Body)() -- debug stuff
end