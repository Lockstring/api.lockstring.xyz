from datetime import datetime, timedelta
import hashlib
import hmac
import binascii

SERVER_SECRET_HEX = "3b66bf61c557262ac490aa6a8db0142b8546dab39ff14ce8e6666f9f0458ced8"

SERVER_SECRET = binascii.unhexlify(SERVER_SECRET_HEX)

def gen_hmac(raw_hwid: str):
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