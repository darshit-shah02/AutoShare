from fastapi import APIRouter, HTTPException
from passlib.context import CryptContext
from jose import jwt
from datetime import datetime, timedelta

from app.models.user import CustomerRegister, DriverRegister, LoginRequest, AuthResponse
from app.database import supabase
from app.config import settings

router = APIRouter()
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# ── Helpers ───────────────────────────────────────────────────────────────────

def hash_password(password: str) -> str:
    return pwd_context.hash(password[:72])  # bcrypt 72-byte limit

def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain[:72], hashed)  # same limit on verify

def create_token(data: dict) -> str:
    payload = data.copy()
    payload["exp"] = datetime.utcnow() + timedelta(
        minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES
    )
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)

# ── Register Customer ─────────────────────────────────────────────────────────

@router.post("/register/customer", response_model=AuthResponse)
def register_customer(data: CustomerRegister):
    # Check if email already exists
    existing = supabase.table("users").select("id").eq("email", data.email).execute()
    if existing.data:
        raise HTTPException(status_code=400, detail="Email already registered")

    # Check if phone already exists
    existing_phone = supabase.table("users").select("id").eq("phone", data.phone).execute()
    if existing_phone.data:
        raise HTTPException(status_code=400, detail="Phone number already registered")

    # Insert new customer
    result = supabase.table("users").insert({
        "name": data.name,
        "email": data.email,
        "phone": data.phone,
        "password_hash": hash_password(data.password),
        "gender": data.gender,
    }).execute()

    if not result.data:
        raise HTTPException(status_code=500, detail="Registration failed")

    user = result.data[0]
    token = create_token({"sub": user["id"], "role": "customer"})

    return AuthResponse(
        access_token=token,
        role="customer",
        user_id=user["id"],
        name=user["name"]
    )

# ── Register Driver ───────────────────────────────────────────────────────────

@router.post("/register/driver", response_model=AuthResponse)
def register_driver(data: DriverRegister):
    # Check email
    existing = supabase.table("drivers").select("id").eq("email", data.email).execute()
    if existing.data:
        raise HTTPException(status_code=400, detail="Email already registered")

    # Check phone
    existing_phone = supabase.table("drivers").select("id").eq("phone", data.phone).execute()
    if existing_phone.data:
        raise HTTPException(status_code=400, detail="Phone number already registered")

    # Check vehicle number
    existing_vehicle = supabase.table("drivers").select("id").eq("vehicle_number", data.vehicle_number).execute()
    if existing_vehicle.data:
        raise HTTPException(status_code=400, detail="Vehicle number already registered")

    # Insert new driver
    result = supabase.table("drivers").insert({
        "name": data.name,
        "email": data.email,
        "phone": data.phone,
        "password_hash": hash_password(data.password),
        "vehicle_number": data.vehicle_number,
        "license_number": data.license_number,
        "gender": data.gender,
    }).execute()

    if not result.data:
        raise HTTPException(status_code=500, detail="Registration failed")

    driver = result.data[0]
    token = create_token({"sub": driver["id"], "role": "driver"})

    return AuthResponse(
        access_token=token,
        role="driver",
        user_id=driver["id"],
        name=driver["name"]
    )

# ── Login ─────────────────────────────────────────────────────────────────────

@router.post("/login", response_model=AuthResponse)
def login(data: LoginRequest):
    table = "users" if data.role == "customer" else "drivers"

    result = supabase.table(table).select("*").eq("email", data.email).execute()

    if not result.data:
        raise HTTPException(status_code=401, detail="Invalid email or password")

    account = result.data[0]

    if not verify_password(data.password, account["password_hash"]):
        raise HTTPException(status_code=401, detail="Invalid email or password")

    token = create_token({"sub": account["id"], "role": data.role})

    return AuthResponse(
        access_token=token,
        role=data.role,
        user_id=account["id"],
        name=account["name"]
    )