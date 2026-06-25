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

        # Calculate fare — base ₹10 + ₹2 per 100 meters
        distance = driver["distance_meters"]
        fare = round(10 + (distance / 100) * 2, 0)

        autos.append({
            "driver_id": str(driver["driver_id"]),
            "name": driver["name"],
            "phone": driver["phone"],
            "vehicle_number": driver["vehicle_number"],
            "rating": float(driver["rating"]),
            "distance_meters": round(distance, 0),
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
def book_ride(data: RideRequest):
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
    fare = round(10 + (distance_meters / 100) * 2, 0)

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

    # Step 6 — Return ride details including nearest route points
    # Flutter will use these to show walking path to/from route
    pickup_nearest_data = pickup_nearest.data if pickup_nearest.data else {}
    dropoff_nearest_data = dropoff_nearest.data if dropoff_nearest.data else {}

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

    # Notify customer via WebSocket
    await manager.send_ride_status(ride_id, new_status)

    return {"message": f"Ride status updated to {new_status}"}

# ── Submit Rating ──────────────────────────────────────────────────────────
# Called after ride completes
# Saves rating and updates driver's average rating

@router.post("/{ride_id}/rating")
def submit_rating(ride_id: str, data: dict):
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