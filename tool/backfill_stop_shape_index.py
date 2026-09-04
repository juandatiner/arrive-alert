"""Adds `si`/`sm` (per-stop shape vertex and metres along) to route assets.

Packs built before these fields existed left the app snapping stops to the
shape at runtime, which mis-measures simplified shapes and loop routes. This
recomputes both from the shape and stops already in each file, so no GTFS
download is needed.

Run from the repo root:  python3 tool/backfill_stop_shape_index.py
"""
import glob, json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shape_snap import snap_stops

ROUTES_DIR = 'assets/transit/routes'


def main():
    files = sorted(glob.glob(os.path.join(ROUTES_DIR, '*.json')))
    for path in files:
        route = json.load(open(path))
        shape = [(p[0], p[1]) for p in route['shape']]
        stops = [(s['lat'], s['lon']) for s in route['stops']]
        route['si'], route['sm'] = snap_stops(shape, stops)
        json.dump(route, open(path, 'w'), separators=(',', ':'),
                  ensure_ascii=False)
    print('routes updated:', len(files))


if __name__ == '__main__':
    main()
