from pydantic import BaseModel


class Check1(BaseModel):
    a: str # hashed key
    b:str # hashed hwid
    c: str # hmac sig
    
class Check2(BaseModel):
    a: str # key
    b: str # sig
    c: str # just to diguise request

class CreateKey(BaseModel):
    key: str
    mins: int
    scriptuid: int

class CreateScript(BaseModel):
    name: str
    script: str
