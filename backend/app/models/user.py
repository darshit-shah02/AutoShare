from pydantic import BaseModel, EmailStr
from typing import Optional

# ── Registration ──────────────────────────────
class CustomerRegister(BaseModel):
    name: str
    email: EmailStr
    phone: str
    password: str
    gender: str = 'Other'

class DriverRegister(BaseModel):
    name: str
    email: EmailStr
    phone: str
    password: str
    vehicle_number: str
    license_number: str
    gender: str = 'Other'

# ── Login ─────────────────────────────────────
class LoginRequest(BaseModel):
    email: EmailStr
    password: str
    role: str  # "customer" or "driver"

# ── Response ──────────────────────────────────
class AuthResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    role: str
    user_id: str
    name: str