from pydantic import BaseModel


class Check1(BaseModel):
    a: str # hashed key
    b:str # hashed hwid
    c: str # hmac sig
    
class Check2(BaseModel):
    key: str
    sig: str

class CreateKey(BaseModel):
    key: str
    mins: int

class CreateScript(BaseModel):
    name: str
    script: str
