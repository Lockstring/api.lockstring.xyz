Old project of mine i decided to release still works and is secure i was going to make this commerical but cba
this alone is pretty powerful edit it a little and you have a powerful auth people are willing to pay for
also obsfuscation has to be done yourself or externally but can be easily added if u have an api key and a brain

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
go to 127.0.0.1:8000/docs once server is there