Old project of mine i decided to release still works and is secure i was going to make this commerical but cba
this alone is pretty powerful edit it a little and you have a powerful auth people are willing to pay for
also obsfuscation has to be done yourself or externally but can be easily added if u have an api key and a brain
it does say that i updated this recently, i didnt i just pushed a new bugfix this repo  is no longer maintained

# lockstring.xyz
Roblox LuaU Whitelist/Auth, includes server and client side

## Install dependencies
```sh
pip install fastapi uvicorn sqlalchemy pydantic python-multipart
```

## Run FastAPI server
You will need to open the terminal in base dir ../lockstring.xyz
```sh
python -m uvicorn Python.main:app --reload
```

## Open hamburger menu
go to `127.0.0.1:8000/docs` once server is running then use the funcs create script, key ext. and it will work

## Run loadstring
in game run this
```lua
skey="[Yourkey]"
loadstring(game:HttpGet("http://127.0.0.1:8000/[your script url]/run"))()
```

## Extra Notes
> you would want to add obsfucation to the client automatically using a commerically sold auths api i wont suggest any specific ones
> you will want to host it either for free locally using smthn like ngrok or u can set it up perm on cloudflare with a domain but you can figure this out urself
> script key is a option on the api when creating key but it will be random u can change this in source
> if it doesnt work dm me on discord @0x55_

IF YOU DO HOST IT AND NOT LOCAL HOST CHANGE URLS IN CLIENT.LUA