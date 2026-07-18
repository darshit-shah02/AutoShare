from fastapi import APIRouter, HTTPException
from app.models.ride import RideRequest
from app.database import supabase
from app.websockets.location import manager
import httpx


router = APIRouter()

# ── Get Nearest Autos ──────────────────────────────────────────────────────
# Customer sends their pickup location
# We find all online drivers within 5km using PostGIS ST_DWithin
# Also calculates the nearest point on the fixed route for each driver
# Returns sorted list — closest driver first

@router.get("/nearby-autos")
def get_nearby_autos(
    pickup_lat: float,
    pickup_lng: float,
    dropoff_lat: float,
    dropoff_lng: float
):
    # Step 1 — Find online drivers near pickup location
    drivers_result = supabase.rpc("get_nearby_drivers", {
        "user_lat": pickup_lat,
        "user_lng": pickup_lng,
        "radius_m": 5000
    }).execute()

    if not drivers_result.data:
        return []

    # Step 2 — Get the fixed route from database
    route_result = supabase.table("fixed_routes").select("*").limit(1).execute()
    if not route_result.data:
        raise HTTPException(status_code=404, detail="No fixed route found")

    route_id = route_result.data[0]["id"]

    # Step 3 — For each driver, calculate nearest point on route
    # and estimate fare based on distance along route
    autos = []
    for driver in drivers_result.data:
        # Get nearest point on fixed route to dropoff location
        nearest = supabase.rpc("get_nearest_point_on_route", {
            "route_id": route_id,
            "point_lat": dropoff_lat,
            "point_lng": dropoff_lng
        }).execute()

        ride_distance_result = supabase.rpc("get_route_distance", {
            "route_id": route_id,
            "pickup_lat": pickup_lat,
            "pickup_lng": pickup_lng,
            "dropoff_lat": dropoff_lat,
            "dropoff_lng": dropoff_lng
        }).execute()

        ride_distance = float(ride_distance_result.data) if ride_distance_result.data else 1000
        ride_km = ride_distance / 1000

        # Same fare slabs as Flutter
        if ride_km <= 1: fare = 10
        elif ride_km <= 3: fare = 20
        elif ride_km <= 5: fare = 30
        elif ride_km <= 7: fare = 40
        elif ride_km <= 10: fare = 50
        else: fare = 50 + (((ride_km - 10) / 2).__ceil__()) * 10

        autos.append({
            "driver_id": str(driver["driver_id"]),
            "name": driver["name"],
            "phone": driver["phone"],
            "vehicle_number": driver["vehicle_number"],
            "rating": float(driver["rating"]),
            "distance_meters": round(float(driver["distance_meters"]), 0),
            "fare": fare,
            "latitude": driver["latitude"],
            "longitude": driver["longitude"],
            "route_id": route_id,
        })

    return autos

# ── Book a Ride ────────────────────────────────────────────────────────────
# Called when customer taps "Select this Auto"
# Creates a ride record in database with status "requested"
# Driver will then accept/reject it

@router.post("/book")
async def book_ride(data: RideRequest):
    # Step 1 — Get fixed route
    route_result = supabase.table("fixed_routes").select("*").limit(1).execute()
    if not route_result.data:
        raise HTTPException(status_code=404, detail="No fixed route found")

    route_id = route_result.data[0]["id"]

    # Step 2 — Find nearest point on route to pickup location
    # This is where the auto will stop to pick up the customer
    pickup_nearest = supabase.rpc("get_nearest_point_on_route", {
        "route_id": route_id,
        "point_lat": data.pickup_latitude,
        "point_lng": data.pickup_longitude
    }).execute()

    # Step 3 — Find nearest point on route to dropoff location
    # This is where the auto will drop the customer
    dropoff_nearest = supabase.rpc("get_nearest_point_on_route", {
        "route_id": route_id,
        "point_lat": data.dropoff_latitude,
        "point_lng": data.dropoff_longitude
    }).execute()

    # Step 4 — Calculate distance and fare
    distance = supabase.rpc("get_route_distance", {
        "route_id": route_id,
        "pickup_lat": data.pickup_latitude,
        "pickup_lng": data.pickup_longitude,
        "dropoff_lat": data.dropoff_latitude,
        "dropoff_lng": data.dropoff_longitude
    }).execute()

    distance_meters = distance.data if distance.data else 1000
    ride_km = float(distance_meters) / 1000

    if ride_km <= 1: fare = 10
    elif ride_km <= 3: fare = 20
    elif ride_km <= 5: fare = 30
    elif ride_km <= 7: fare = 40
    elif ride_km <= 10: fare = 50
    else: fare = 50 + (int((ride_km - 10) / 2) + 1) * 10

    # Step 5 — Create ride record in database
    pickup_point = f"POINT({data.pickup_longitude} {data.pickup_latitude})"
    dropoff_point = f"POINT({data.dropoff_longitude} {data.dropoff_latitude})"

    ride_result = supabase.table("rides").insert({
        "user_id": data.user_id,
        "driver_id": data.driver_id,
        "route_id": route_id,
        "pickup_location": pickup_point,
        "dropoff_location": dropoff_point,
        "pickup_address": data.pickup_address,
        "dropoff_address": data.dropoff_address,
        "fare": fare,
        "distance_meters": distance_meters,
        "status": "requested",
    }).execute()

    if not ride_result.data:
        raise HTTPException(status_code=500, detail="Failed to create ride")

    ride = ride_result.data[0]
    ride_id = ride["id"]

    # Step 6 — Return ride details including nearest route points
    # Flutter will use these to show walking path to/from route
    pickup_nearest_data = pickup_nearest.data if pickup_nearest.data else {}
    dropoff_nearest_data = dropoff_nearest.data if dropoff_nearest.data else {}

    # ── Notify driver via WebSocket ────────────────────────────────────────
    # Send ride request to driver's WebSocket connection
    # Driver sees popup with ride details
    # import asyncio
    # import math

    # # Calculate distance from driver to pickup
    # driver_result = supabase.table("drivers").select(
    #     "id"
    # ).eq("id", data.driver_id).execute()

    # driver_to_pickup = supabase.rpc("get_route_distance", {
    #     "route_id": route_id,
    #     "pickup_lat": data.pickup_latitude,
    #     "pickup_lng": data.pickup_longitude,
    #     "dropoff_lat": data.pickup_latitude,
    #     "dropoff_lng": data.pickup_longitude
    # }).execute()

    ride_request_message = {
        "type": "ride_request",
        "ride_id": ride_id,
        "user_id": data.user_id,
        "pickup_address": data.pickup_address,
        "dropoff_address": data.dropoff_address,
        "pickup_lat": data.pickup_latitude,
        "pickup_lng": data.pickup_longitude,
        "dropoff_lat": data.dropoff_latitude,
        "dropoff_lng": data.dropoff_longitude,
        "fare": fare,
        "distance_meters": distance_meters,
    }

    # Now we can properly await since function is async
    try:
        await manager.broadcast_to_driver(str(data.driver_id), ride_request_message)
        print(f"Ride request sent to driver {data.driver_id}")
    except Exception as e:
        print(f"WebSocket notify failed: {e}")

    return {
        "ride_id": ride["id"],
        "status": ride["status"],
        "fare": fare,
        "distance_meters": distance_meters,
        "pickup_nearest_point": pickup_nearest_data,
        "dropoff_nearest_point": dropoff_nearest_data,
    }

# ── Get Walking Path ───────────────────────────────────────────────────────
# Called after booking is confirmed
# Returns two walking paths:
#   1. From user's location → nearest point on fixed route (to board auto)
#   2. From dropoff point on route → user's destination (after exiting auto)
# Uses OSRM public API for walking directions
# OSRM returns a polyline — series of coordinates forming the walking path

@router.get("/walking-path")
async def get_walking_path(
    from_lat: float,
    from_lng: float,
    to_lat: float,
    to_lng: float
):

    # OSRM public API — walking profile
    # Format: /route/v1/foot/lng,lat;lng,lat
    # Note: OSRM uses longitude first, then latitude
    url = (
        f"http://router.project-osrm.org/route/v1/foot/"
        f"{from_lng},{from_lat};{to_lng},{to_lat}"
        f"?overview=full&geometries=geojson"
    )

    async with httpx.AsyncClient() as client:
        response = await client.get(url, timeout=10)

    if response.status_code != 200:
        raise HTTPException(status_code=500, detail="Routing service unavailable")

    data = response.json()

    if not data.get("routes"):
        raise HTTPException(status_code=404, detail="No walking route found")

    route = data["routes"][0]

    # Extract coordinates from GeoJSON
    # Each coordinate is [longitude, latitude] — we flip to [lat, lng] for Flutter
    coordinates = route["geometry"]["coordinates"]
    path = [{"lat": c[1], "lng": c[0]} for c in coordinates]

    return {
        "path": path,                              # list of lat/lng points
        "distance_meters": route["distance"],      # total walking distance
        "duration_seconds": route["duration"],     # estimated walking time
    }

# ── Update Ride Status ─────────────────────────────────────────────────────
# Called by driver when they accept/start/complete a ride
# Also notifies customer via WebSocket

@router.patch("/{ride_id}/status")
async def update_ride_status(ride_id: str, data: dict):
    new_status = data.get("status")

    # Update in database
    result = supabase.table("rides").update({
        "status": new_status
    }).eq("id", ride_id).execute()

    if not result.data:
        raise HTTPException(status_code=404, detail="Ride not found")

    # Notify the driver via WebSocket (best-effort).
    # The customer app polls GET /rides/{ride_id}/status, so no
    # customer WebSocket notification is needed.
    ride = result.data[0] if isinstance(result.data, list) else result.data
    driver_id = ride.get("driver_id")
    if driver_id:
        try:
            await manager.broadcast_to_driver(str(driver_id), {
                "type": "ride_status",
                "ride_id": ride_id,
                "status": new_status,
            })
        except Exception as e:
            print(f"WebSocket notify failed: {e}")

    return {"message": f"Ride status updated to {new_status}"}

# ── Submit Rating ──────────────────────────────────────────────────────────
# Called after ride completes
# Saves rating and updates driver's average rating

@router.post("/{ride_id}/rating")
async def submit_rating(ride_id: str, data: dict):
    rating = data.get("rating")
    if not rating or rating < 1 or rating > 5:
        raise HTTPException(status_code=400, detail="Rating must be 1-5")

    # Get ride details to find driver and user
    ride = supabase.table("rides").select(
        "driver_id, user_id"
    ).eq("id", ride_id).execute()

    if not ride.data:
        raise HTTPException(status_code=404, detail="Ride not found")

    ride_data = ride.data[0] if isinstance(ride.data, list) else ride.data

    # Save rating record
    supabase.table("ratings").insert({
        "ride_id": ride_id,
        "user_id": ride_data["user_id"],
        "driver_id": ride_data["driver_id"],
        "rating": rating
    }).execute()

    # Update driver's average rating
    # Gets all ratings for this driver and calculates new average
    supabase.rpc("update_driver_rating", {
        "driver_id_input": ride_data["driver_id"]
    }).execute()

    return {"message": "Rating submitted successfully"}

# ── Get Fixed Route Coordinates ────────────────────────────────────────────
# Now accepts optional route_id parameter
# If route_id provided → fetch that specific route
# If not → fetch first available route (fallback)

@router.get("/fixed-route")
def get_fixed_route(route_id: str = None):
    if route_id:
        # Fetch specific route by ID
        result = supabase.rpc("get_fixed_route_coordinates_by_id", {
            "route_id_input": route_id
        }).execute()
    else:
        # Fallback — fetch first available route
        result = supabase.rpc("get_fixed_route_coordinates").execute()

    if not result.data:
        raise HTTPException(status_code=404, detail="No fixed route found")

    return {"coordinates": result.data}

# ── Get Nearest Point on Fixed Route ──────────────────────────────────────
# Given a lat/lng, returns the closest point ON the fixed route
# Used by confirm_ride_screen to find where user boards/exits auto

@router.get("/nearest-on-route")
def get_nearest_on_route(lat: float, lng: float):
    # Get fixed route
    route = supabase.table("fixed_routes").select("id").limit(1).execute()
    if not route.data:
        raise HTTPException(status_code=404, detail="No fixed route found")

    route_id = route.data[0]["id"] if isinstance(route.data, list) \
        else route.data["id"]

    result = supabase.rpc("get_nearest_point_on_route", {
        "route_id": route_id,
        "point_lat": lat,
        "point_lng": lng
    }).execute()

    if not result.data:
        raise HTTPException(
            status_code=404,
            detail="Could not find nearest point"
        )

    data = result.data
    if isinstance(data, list):
        return data[0]
    return data

# ── Get All Predefined Routes ──────────────────────────────────────────────
# Returns list of all predefined routes for driver to choose from
# Driver sees this list when they tap "Go Online"

@router.get("/predefined-routes")
def get_predefined_routes():
    result = supabase.table("fixed_routes").select(
        "id, name, start_address, end_address, "
        "total_distance_meters, estimated_duration_minutes, direction"
    ).eq("is_predefined", True).execute()

    data = result.data if isinstance(result.data, list) else []
    return data

# ── Driver Selects a Route ─────────────────────────────────────────────────
# Called when driver confirms which route they'll drive today
# Saves to driver_routes table and marks driver as online on this route

@router.post("/select-route")
def select_driver_route(data: dict):
    driver_id = data.get("driver_id")
    route_id = data.get("route_id")

    if not driver_id or not route_id:
        raise HTTPException(
            status_code=400,
            detail="driver_id and route_id required"
        )

    # Deactivate any previous active routes for this driver
    supabase.table("driver_routes").update({
        "is_active": False,
        "ended_at": "now()"
    }).eq("driver_id", driver_id).eq("is_active", True).execute()

    # Create new active route for driver
    result = supabase.table("driver_routes").insert({
        "driver_id": driver_id,
        "route_id": route_id,
        "is_active": True
    }).execute()

    if not result.data:
        raise HTTPException(
            status_code=500,
            detail="Failed to select route"
        )

    return {"message": "Route selected successfully"}

# ── Get Driver's Current Active Route ─────────────────────────────────────
# Returns the route driver is currently operating on
# Used by customer app to find nearby autos on specific routes

@router.get("/driver-active-route/{driver_id}")
def get_driver_active_route(driver_id: str):
    result = supabase.table("driver_routes").select(
        "route_id, fixed_routes(id, name, start_address, end_address)"
    ).eq("driver_id", driver_id).eq("is_active", True).limit(1).execute()

    if not result.data:
        return {"route": None}

    data = result.data[0] if isinstance(result.data, list) else result.data
    return {"route": data}

# ── Get Ride Status ────────────────────────────────────────────────────────
# Customer polls this every 3 seconds to check if driver accepted
# Returns current ride status + driver details when accepted

@router.get("/{ride_id}/status")
def get_ride_status(ride_id: str):
    result = supabase.table("rides").select(
        "id, status, fare, driver_id, "
        "pickup_address, dropoff_address"
    ).eq("id", ride_id).execute()

    if not result.data:
        raise HTTPException(status_code=404, detail="Ride not found")

    ride = result.data[0] if isinstance(result.data, list) else result.data

    # If accepted — include driver details
    if ride["status"] in ["accepted", "in_progress"] and ride["driver_id"]:
        driver = supabase.table("drivers").select(
            "id, name, phone, vehicle_number, rating"
        ).eq("id", ride["driver_id"]).execute()

        driver_data = driver.data[0] if isinstance(
            driver.data, list) else driver.data

        return {
            "ride_id": ride["id"],
            "status": ride["status"],
            "fare": ride["fare"],
            "driver": driver_data,
        }

    return {
        "ride_id": ride["id"],
        "status": ride["status"],
        "fare": ride["fare"],
        "driver": None,
    }

# ── Update Customer Location ───────────────────────────────────────────────
# Customer sends their live location every 5 seconds after booking
# Driver can see customer location on their map

@router.post("/{ride_id}/customer-location")
def update_customer_location(ride_id: str, data: dict):
    lat = data.get("latitude")
    lng = data.get("longitude")

    if not lat or not lng:
        raise HTTPException(status_code=400, detail="lat/lng required")

    supabase.table("rides").update({
        "pickup_location": f"POINT({lng} {lat})"
    }).eq("id", ride_id).eq("status", "accepted").execute()

    return {"message": "Location updated"}

# ── Get Customer Location ──────────────────────────────────────────────────
# Driver polls this to see customer's live location
# Called every 3 seconds after accepting a ride

@router.get("/{ride_id}/customer-location")
def get_customer_location(ride_id: str):
    result = supabase.rpc("get_customer_location", {
        "ride_id_input": ride_id
    }).execute()

    if not result.data:
        raise HTTPException(status_code=404, detail="Location not found")

    data = result.data
    if isinstance(data, list):
        return data[0]
    return data

# ── Get Pending Ride Request for Driver ────────────────────────────────────
# Driver polls this every 3 seconds as backup to WebSocket
# Returns any pending ride request assigned to this driver
# This ensures driver always gets notified even if WebSocket disconnects

@router.get("/pending-request/{driver_id}")
def get_pending_request(driver_id: str):
    result = supabase.table("rides").select(
        "id, user_id, pickup_address, dropoff_address, "
        "fare, distance_meters, status"
    ).eq("driver_id", driver_id).eq("status", "requested").limit(1).execute()

    if not result.data:
        return {"request": None}

    data = result.data[0] if isinstance(result.data, list) else result.data
    return {
        "request": {
            "type": "ride_request",
            "ride_id": data["id"],
            "pickup_address": data["pickup_address"],
            "dropoff_address": data["dropoff_address"],
            "fare": data["fare"],
            "distance_meters": data["distance_meters"],
        }
    }