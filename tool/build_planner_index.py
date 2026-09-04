"""Builds the journey-planner index from the per-route assets already bundled.

The per-route files answer "draw route X", but a planner needs the opposite
lookup - "which routes touch this corner, and how far along each one is that
stop" - for all 1044 routes at once. Loading 1044 files on a phone to answer
one query is out, so the whole thing is flattened into a single asset:
arrays parallel to each route's own stop list, so a (route, stop) pair found
here maps straight onto RouteMapScreen's stop indices.

Needs `si`/`sm` in the route files - run tool/backfill_stop_shape_index.py
first on packs built before those existed.

Run from the repo root:  python3 tool/build_planner_index.py
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shape_snap import snap_stops

ROUTES_DIR = 'assets/transit/routes'
INDEX_PATH = 'assets/transit/routes_index.json'
OUT_PATH = 'assets/transit/planner.json'


def main():
    summaries = json.load(open(INDEX_PATH))
    routes, route_stops, route_meters = [], [], []
    stop_ids = {}          # stop_id -> index into `stops`
    stops = []             # [name, lat, lon]

    for summary in summaries:
        path = os.path.join(ROUTES_DIR, f"{summary['id']}.json")
        if not os.path.exists(path):
            continue
        route = json.load(open(path))
        if not route['shape'] or not route['stops']:
            continue

        meters = route.get('sm')
        if meters is None:
            _, meters = snap_stops(
                [(p[0], p[1]) for p in route['shape']],
                [(s['lat'], s['lon']) for s in route['stops']])

        indices = []
        for stop in route['stops']:
            sid = stop['id']
            idx = stop_ids.get(sid)
            if idx is None:
                idx = len(stops)
                stop_ids[sid] = idx
                stops.append([stop['n'], stop['lat'], stop['lon']])
            indices.append(idx)

        routes.append([route['id'], route['short'], route['long'], route['kind']])
        route_stops.append(indices)
        route_meters.append(meters)

    payload = {
        'routes': routes,
        'stops': stops,
        'rs': route_stops,
        'rm': route_meters,
    }
    json.dump(payload, open(OUT_PATH, 'w'), separators=(',', ':'), ensure_ascii=False)
    pairs = sum(len(s) for s in route_stops)
    print('routes:', len(routes), 'stops:', len(stops), 'route-stop pairs:', pairs)
    print('size:', round(os.path.getsize(OUT_PATH) / 1024 / 1024, 2), 'MB')


if __name__ == '__main__':
    main()
