from datetime import datetime, timedelta
import hashlib
import hmac
import binascii

def gen_hmac(raw_hwid: str, nonce:str):
    SERVER_SECRET = binascii.unhexlify(nonce)
    return hmac.new(
        SERVER_SECRET,
        raw_hwid.encode("utf-8"),
        hashlib.sha256
    ).hexdigest()

def calculate_expiry(hours: int = 0, minutes: int = 0, seconds: int = 0):
    return datetime.utcnow() + timedelta(
        hours=hours,
        minutes=minutes,
        seconds=seconds
    )