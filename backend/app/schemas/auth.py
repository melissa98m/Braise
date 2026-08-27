from pydantic import BaseModel


class OTPRequest(BaseModel):
    phone: str


class OTPRequestResponse(BaseModel):
    message: str
    debug_code: str | None = None


class OTPVerify(BaseModel):
    phone: str
    code: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
