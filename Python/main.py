from fastapi import FastAPI, Depends, Request, UploadFile, File
from Python.database import engine, get_db, Base
from Python.models import Script, Key, Session
from Python.functions import calculate_expiry, gen_hmac, SERVER_SECRET
from Python.schemas import Check1, Check2, CreateKey
from datetime import datetime, timedelta
from fastapi.responses import FileResponse, PlainTextResponse
import secrets
import random

app = FastAPI()
Base.metadata.create_all(bind=engine)

@app.post("/create/key")
async def create_key(info: CreateKey, db: Session = Depends(get_db)):
    key_value = secrets.token_hex(16)

    newkey = Key(
        key=key_value,
        script_uid=1,
        hashed_key=gen_hmac(key_value),
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
    script = Script(
        name=name,
        script=content,
        script_url=secrets.token_urlsafe(16)
    )
    db.add(script)
    db.commit()
    db.refresh(script)

    return {"id": script.uid}

@app.get("/run")
async def runscript():
    return FileResponse(path=r"C:\Users\jakem\Desktop\straingame-main\lockstring.xyz\Lua\client.lua",media_type="text/plain")

@app.post("/check/1")
async def check1(info:Check1, request: Request, db: Session = Depends(get_db)):
    key = db.query(Key).filter(Key.key == info.a).first()
    if not key:
        return {"error": "print('Wrong key used')"}

    x = gen_hmac(key.key + "|" + info.b)

    headers = dict(request.headers)
    found = False
    for name, value in headers.items():
        if info.b in gen_hmac(value):
            found = True
            matched_header = name
            matched_header_value = gen_hmac(value)
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

    sig = gen_hmac(session_token)
    fake_sessions = [secrets.token_hex(32) for _ in range(12)]
    fake_sigs = [secrets.token_hex(32) for _ in range(12)]
    
    responses = [
        {"a": fake_sessions[0],"b":fake_sigs[0]},
        {"a": fake_sessions[1],"b":fake_sigs[1]},
        {"a": fake_sessions[2],"b":fake_sigs[2]},
        {"a": fake_sessions[3],"b":fake_sigs[3]},
        {"a": fake_sessions[4],"b":fake_sigs[4]},
        {"a": fake_sessions[5],"b":fake_sigs[5]},
        {"a": fake_sessions[6],"b":fake_sigs[6]},
        {"a": fake_sessions[7],"b":fake_sigs[7]},
        {"a": fake_sessions[8],"b":fake_sigs[8]},
        {"a": fake_sessions[9],"b":fake_sigs[9]},
        {"a": fake_sessions[10],"b":fake_sigs[10]},
        {"a": fake_sessions[11],"b":fake_sigs[11]}
    ]

    real_index = random.randint(0,11)
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
        Session.key_value == info.key,
        Session.used == False,
        Session.expiresat > datetime.utcnow()
    ).first()

    if not session:
        return {"error":"print('bad session')"}

    combined_string = session.token + "|" + session.hwid
    sig = gen_hmac(combined_string)
    if sig == info.sig:
        session.used = True
        db.commit()
        
        return {"success":1}

    # mark session as used
    session.used = True
    db.commit()

    return {"error":"print('bad signature')"}