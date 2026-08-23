from fastapi import FastAPI, Depends, Request, UploadFile, File
from Python.database import engine, get_db, Base
from Python.models import Script, Key, Session
from Python.functions import calculate_expiry, gen_hmac
from Python.schemas import Check1, Check2, CreateKey
from datetime import datetime, timedelta
from fastapi.responses import FileResponse, PlainTextResponse
import secrets
import random

app = FastAPI()
Base.metadata.create_all(bind=engine)

@app.post("/create/key")
async def create_key(info: CreateKey, db: Session = Depends(get_db)):
    script = db.query(Script).filter(Script.uid == info.scriptuid).first()

    if not script:
        return {"error":"not found"}
    
    key_value = secrets.token_hex(16)

    newkey = Key(
        key=key_value,
        script_uid=info.scriptuid,
        script_url=script.script_url,
        hashed_key=gen_hmac(key_value,script.nonce),
        expiresat=datetime.utcnow() + timedelta(minutes=info.mins)
    )

    db.add(newkey)
    db.commit()
    db.refresh(newkey)

    return {
        newkey
    }

@app.post("/create/script")
async def create_script(name: str, lua_file: UploadFile = File(...), db:Session = Depends(get_db)):
    content = await lua_file.read()
    with open(r"C:\Users\jakem\Desktop\straingame-main\lockstring.xyz\Lua\client.lua", "r") as f:
        lua = f.read()
    nonce = secrets.token_hex(32)
    parts = [nonce[i:i+16] for i in range(0, 64, 16)]
    for i, part in enumerate(parts):
        lua = lua.replace(f"%PLACEHOLDER{i}%", part)
    script_content = content.decode().replace("]=]", "] = ]")
    lua = lua.replace("%SCRIPT%", script_content)
    script = Script(
        name=name,
        nonce=nonce,
        script=lua.encode(),
        script_url=secrets.token_urlsafe(16)
    )
    db.add(script)
    db.commit()
    db.refresh(script)

    return {"id": script.uid}

@app.get("/{scripturl}/run", response_class=PlainTextResponse)
async def runscript(scripturl: str, db: Session = Depends(get_db)):
    script = db.query(Script).filter(Script.script_url == scripturl).first()

    if not script:
        return "script not found"

    return script.script.decode()

@app.post("/check/1")
async def check1(info:Check1, request: Request, db: Session = Depends(get_db)):
    key = db.query(Key).filter(Key.key == info.a).first()
    if not key:
        return {"error": "print('Wrong key used')"}
    key.executions = key.executions + 1
    script = db.query(Script).filter(Script.script_url == key.script_url).first()

    x = gen_hmac(key.key + "|" + info.b,script.nonce)

    headers = dict(request.headers)
    found = False
    for name, value in headers.items():
        if info.b in gen_hmac(value,script.nonce):
            found = True
            matched_header = name
            matched_header_value = gen_hmac(value,script.nonce)
            break

    if not found:
        return {"error": "print('Tampering detected')"}
    if matched_header_value != info.b:
        return {"error": "print('Tampering detected')"}
    if key.expiresat <= datetime.utcnow():
        return {"error": "print('Key expired')"}
    if x != info.c:
        return {"error": "print('Tampering detected')"}
    if key.hwid is None:
        if key.claimed_at is None:
            key.hwid = info.b
            key.claimed_at = datetime.utcnow()
            db.commit()
        else:
            return {"error": "print('Tampering detected')"}
    if key.hwid != info.b:
        return {"error": "print('HWID mismatch')"}
    session_token = secrets.token_hex(32)
    new_session = Session(
        token=session_token,
        key_value=key.key,
        hwid=key.hwid,
        ip=request.client.host,
        expiresat=datetime.utcnow() + timedelta(seconds=5),
        used=False
    )

    sig = gen_hmac(session_token,script.nonce)
    fake_sessions = [secrets.token_hex(32) for _ in range(12)]
    fake_sigs = [secrets.token_hex(32) for _ in range(12)]
    
    responses = [
        {"a": fake_sessions[0],"b":fake_sigs[0]},
        {"a": fake_sessions[1],"b":fake_sigs[1]},
        {"a": fake_sessions[2],"b":fake_sigs[2]},
        {"a": fake_sessions[3],"b":fake_sigs[3]}
    ]

    real_index = random.randint(0,4)
    responses[real_index] = {"a": session_token,"b":sig}

    db.add(new_session)
    db.commit()
    db.refresh(new_session)
    return {
        "responses": responses
    }

@app.post("/check/2")
async def check2(info: Check2, db: Session = Depends(get_db)):
    session = db.query(Session).filter(
        Session.key_value == info.a,
        Session.used == False,
        Session.expiresat > datetime.utcnow()
    ).first()

    if not session:
        return {"error":"print('bad session')"}
    
    key = db.query(Key).filter(Key.key == session.key_value).first()
    script = db.query(Script).filter(Script.script_url == key.script_url).first()

    combined_string = session.token + "|" + session.hwid
    sig = gen_hmac(combined_string, script.nonce)
    real = [secrets.token_hex(32) for _ in range(8)]
    responses = [
        {"a":real[0],"b":real[4]},
        {"a":real[1],"b":real[5]},
        {"a":real[2],"b":real[6]},
        {"a":real[3],"b":real[7]}
    ]
    if sig == info.b:
        session.used = True
        db.commit()
        real_index = random.randint(0,3)
        test = real_index+4
        responses[real_index] = {"a":gen_hmac(real[test],script.nonce),"b":real[test]}
        print(responses)
        return responses

    # mark session as used
    session.used = True
    db.commit()

    return {"error":"print('bad signature')"}

@app.post("/check/{id}")
async def fake_check(id:str, db: Session = Depends(get_db)):
    script = db.query(Script).filter(Script.uid == id).first()
    if not script:
        return "noo"
    return script