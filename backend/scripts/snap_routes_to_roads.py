"""
One-time script: snap all fixed_routes geometries to real roads.

Problem:
    Routes were inserted manually with only 2 points (start + end),
    so the app draws a straight line instead of following roads.

Fix:
    For every route in fixed_routes:
      1. Read its current coordinates (via the same RPC the app uses)
      2. Take the first and last points (start + end)
      3. Ask OSRM (driving profile) for the real road path between them
      4. Overwrite the stored geometry with the full road-following LINESTRING
      5. Also update total_distance_meters / estimated_duration_minutes

Usage (from the backend/ directory, with your .env present):
    python -m scripts.snap_routes_to_roads          # dry run (prints only)
    python -m scripts.snap_routes_to_roads --apply  # actually update DB
"""

import sys
import time

import httpx

# Reuse the backend's configured Supabase client (reads backend/.env)
from app.database import supabase

# ── Config ──────────────────────────────────────────────────────────────────
# Change this if your geometry column in fixed_routes has a different name.
GEOMETRY_COLUMN = "route_path"

OSRM_URL = (
    "http://router.project-osrm.org/route/v1/driving/"
    "{from_lng},{from_lat};{to_lng},{to_lat}"
    "?overview=full&geometries=geojson"
)


def get_route_endpoints(route_id: str):
    """Return (start, end) lat/lng of a route using the existing RPC."""
    result = supabase.rpc(
        "get_fixed_route_coordinates_by_id",
        {"route_id_input": route_id},
    ).execute()

    coords = result.data or []
    if len(coords) < 2:
        return None, None

    first, last = coords[0], coords[-1]
    return (
        (first["latitude"], first["longitude"]),
        (last["latitude"], last["longitude"]),
    )


def fetch_driving_path(start, end):
    """Call OSRM driving profile. Returns (coords, distance_m, duration_s).

    coords is a list of (lng, lat) tuples following actual roads.
    """
    url = OSRM_URL.format(
        from_lng=start[1], from_lat=start[0],
        to_lng=end[1], to_lat=end[0],
    )
    response = httpx.get(url, timeout=15)
    response.raise_for_status()
    data = response.json()

    if not data.get("routes"):
        raise RuntimeError("OSRM returned no routes")

    route = data["routes"][0]
    coords = [(c[0], c[1]) for c in route["geometry"]["coordinates"]]
    return coords, route["distance"], route["duration"]


def to_wkt_linestring(coords):
    """Convert [(lng, lat), ...] to PostGIS WKT: LINESTRING(lng lat, ...)"""
    points = ", ".join(f"{lng} {lat}" for lng, lat in coords)
    return f"SRID=4326;LINESTRING({points})"


def main():
    apply_changes = "--apply" in sys.argv

    routes = supabase.table("fixed_routes").select("id, name").execute()
    if not routes.data:
        print("No routes found in fixed_routes table.")
        return

    print(f"Found {len(routes.data)} route(s). Mode: "
          f"{'APPLY (updating DB)' if apply_changes else 'DRY RUN (no changes)'}\n")

    for route in routes.data:
        route_id = route["id"]
        name = route.get("name", "unnamed")
        print(f"── Route: {name} ({route_id})")

        start, end = get_route_endpoints(route_id)
        if not start:
            print("   SKIP: could not read current coordinates\n")
            continue

        print(f"   Start: {start}  End: {end}")

        try:
            coords, distance_m, duration_s = fetch_driving_path(start, end)
        except Exception as exc:
            print(f"   SKIP: OSRM error: {exc}\n")
            continue

        print(f"   OSRM path: {len(coords)} points, "
              f"{distance_m / 1000:.2f} km, {duration_s / 60:.0f} min")

        if len(coords) < 3:
            print("   WARNING: OSRM returned very few points — "
                  "start/end may be off-road or too close.\n")

        if apply_changes:
            wkt = to_wkt_linestring(coords)
            supabase.table("fixed_routes").update({
                GEOMETRY_COLUMN: wkt,
                "total_distance_meters": round(distance_m),
                "estimated_duration_minutes": round(duration_s / 60),
            }).eq("id", route_id).execute()
            print("   UPDATED in database.\n")
        else:
            print("   (dry run — nothing written)\n")

        # Be polite to the free public OSRM server
        time.sleep(1)

    print("Done." if apply_changes
          else "Dry run complete. Re-run with --apply to update the database.")


if __name__ == "__main__":
    main()
