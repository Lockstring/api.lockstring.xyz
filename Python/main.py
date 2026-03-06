from fastapi import FastAPI, Depends, Request
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
        expiresat=datetime.utcnow() + timedelta(minutes=info.mins)
    )

    db.add(newkey)
    db.commit()
    db.refresh(newkey)

    return {
        newkey
    }

@app.get("/run")
async def runscript():
    return FileResponse(path=r"C:\Users\jakem\Desktop\straingame-main\lockstring.xyz\Lua\client.lua",media_type="text/plain")

@app.post("/check/1")
async def check1(info:Check1, request: Request, db: Session = Depends(get_db)):
    key = db.query(Key).filter(Key.key == info.key).first()
    if not key:
        return {"error": "Wrong key used"}
    if key.hwid is None:
        if key.claimed_at is None:
            key.hwid = info.hwid
            key.claimed_at = datetime.utcnow()
            db.commit()
        else:
            return {"error": "Tampering detected"}
    if key.hwid != info.hwid:
        return {"error": "HWID mismatch"}
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
    fake_sessions = [secrets.token_hex(32) for _ in range(10)]
    fake_sigs = [secrets.token_hex(32) for _ in range(10)]

    
    responses = [
        {"session": fake_sessions[0],"sig":fake_sigs[0]},
        {"session": fake_sessions[1],"sig":fake_sigs[1]},
        {"session": fake_sessions[2],"sig":fake_sigs[2]},
        {"session": fake_sessions[3],"sig":fake_sigs[3]}
    ]

    real_index = random.randint(0,3)
    responses[real_index] = {"session": session_token,"sig":sig}

    db.add(new_session)
    db.commit()
    db.refresh(new_session)
    return {
        "responses": responses
    }

@app.post("/check/2", response_class=PlainTextResponse)
async def check2(info: Check2, db: Session = Depends(get_db)):
    session = db.query(Session).filter(
        Session.key_value == info.key,
        Session.used == False,
        Session.expiresat > datetime.utcnow()
    ).first()

    if not session:
        return "print('bad session')"

    combined_string = session.token + "|" + session.hwid
    sig = gen_hmac(combined_string)
    if sig == info.sig:
        session.used = True
        db.commit()
        return "print('success sigma lockstring')"

    # mark session as used
    session.used = True
    db.commit()

    return "print('bad signature')"