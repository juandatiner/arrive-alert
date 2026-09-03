"""Turns the 620MB TransMilenio GTFS feed into compact per-route assets.

Only one trip per route is kept (the feed has exactly one shape per route, so
every trip of a route walks the same path - the rest are just departure times),
which is what collapses stop_times.txt from 544MB to a few hundred KB.
"""
import csv, json, math, os, sys, collections

csv.field_size_limit(sys.maxsize)
GTFS = 'gtfs'
OUT = 'transit_out'

# agency_id -> the three buckets the app's UI offers, plus cable.
KIND_BY_AGENCY = {
    '1': 'troncal',      # Transmilenio-Troncal
    '6': 'troncal',      # Transmilenio-Dual
    '2': 'alimentador',  # Transmilenio-Alimentadores
    '3': 'zonal',        # Zonal-Urbano
    '4': 'zonal',        # Zonal-Complementario
    '5': 'zonal',        # Zonal-Especial
    '7': 'cable',        # TransMiCable
}

# ~5.5 m at Bogota's latitude - well under what's visible at street zoom, and
# it cuts the densely-sampled GTFS shapes down by an order of magnitude.
SIMPLIFY_TOL = 0.00005


def perpendicular_distance(pt, start, end):
    if start == end:
        return math.hypot(pt[0] - start[0], pt[1] - start[1])
    x0, y0 = pt
    x1, y1 = start
    x2, y2 = end
    num = abs((y2 - y1) * x0 - (x2 - x1) * y0 + x2 * y1 - y2 * x1)
    den = math.hypot(y2 - y1, x2 - x1)
    return num / den


def douglas_peucker(points, tol):
    if len(points) < 3:
        return points
    stack = [(0, len(points) - 1)]
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    while stack:
        first, last = stack.pop()
        max_d, idx = 0.0, -1
        for i in range(first + 1, last):
            d = perpendicular_distance(points[i], points[first], points[last])
            if d > max_d:
                max_d, idx = d, i
        if max_d > tol and idx != -1:
            keep[idx] = True
            stack.append((first, idx))
            stack.append((idx, last))
    return [p for p, k in zip(points, keep) if k]


def main():
    os.makedirs(f'{OUT}/routes', exist_ok=True)

    routes = {}
    for r in csv.DictReader(open(f'{GTFS}/routes.txt')):
        kind = KIND_BY_AGENCY.get(r['agency_id'])
        if kind is None:
            continue
        routes[r['route_id']] = {
            'id': r['route_id'],
            'short': r['route_short_name'].strip(),
            'long': r['route_long_name'].strip(),
            'kind': kind,
            'color': r['route_color'].strip() or '3B6FE0',
        }
    print('routes:', len(routes))

    # One representative trip per route + its shape.
    trip_for_route, shape_for_route = {}, {}
    for t in csv.DictReader(open(f'{GTFS}/trips.txt')):
        rid = t['route_id']
        if rid in routes and rid not in trip_for_route:
            trip_for_route[rid] = t['trip_id']
            shape_for_route[rid] = t['shape_id']
    wanted_trips = {tid: rid for rid, tid in trip_for_route.items()}
    print('representative trips:', len(wanted_trips))

    stops = {}
    for s in csv.DictReader(open(f'{GTFS}/stops.txt')):
        stops[s['stop_id']] = (
            s['stop_name'].strip(),
            float(s['stop_lat']),
            float(s['stop_lon']),
        )
    print('stops:', len(stops))

    # Single streaming pass over the 544MB stop_times.
    seq_by_route = collections.defaultdict(list)
    scanned = 0
    with open(f'{GTFS}/stop_times.txt', newline='') as fh:
        for row in csv.DictReader(fh):
            scanned += 1
            rid = wanted_trips.get(row['trip_id'])
            if rid is None:
                continue
            seq_by_route[rid].append(
                (int(row['stop_sequence']), row['stop_id'])
            )
    print('stop_times scanned:', scanned, 'routes with stops:', len(seq_by_route))

    # Shapes, also single pass.
    wanted_shapes = {sid: rid for rid, sid in shape_for_route.items()}
    shape_pts = collections.defaultdict(list)
    with open(f'{GTFS}/shapes.txt', newline='') as fh:
        for row in csv.DictReader(fh):
            rid = wanted_shapes.get(row['shape_id'])
            if rid is None:
                continue
            shape_pts[rid].append((
                int(row['shape_pt_sequence']),
                float(row['shape_pt_lat']),
                float(row['shape_pt_lon']),
            ))
    print('routes with shape:', len(shape_pts))

    index = []
    raw_pts = simp_pts = 0
    for rid, meta in routes.items():
        seq = sorted(seq_by_route.get(rid, []))
        stop_list = []
        for _, sid in seq:
            info = stops.get(sid)
            if info is None:
                continue
            name, lat, lon = info
            stop_list.append({
                'id': sid,
                'n': name,
                'lat': round(lat, 5),
                'lon': round(lon, 5),
            })
        pts = [(la, lo) for _, la, lo in sorted(shape_pts.get(rid, []))]
        raw_pts += len(pts)
        pts = douglas_peucker(pts, SIMPLIFY_TOL)
        simp_pts += len(pts)
        if not stop_list or not pts:
            continue

        json.dump(
            {
                'id': rid,
                'short': meta['short'],
                'long': meta['long'],
                'kind': meta['kind'],
                'color': meta['color'],
                'shape': [[round(la, 5), round(lo, 5)] for la, lo in pts],
                'stops': stop_list,
            },
            open(f'{OUT}/routes/{rid}.json', 'w'),
            separators=(',', ':'),
            ensure_ascii=False,
        )
        index.append({
            'id': rid,
            's': meta['short'],
            'l': meta['long'],
            'k': meta['kind'],
            'c': meta['color'],
            'n': len(stop_list),
        })

    json.dump(index, open(f'{OUT}/routes_index.json', 'w'),
              separators=(',', ':'), ensure_ascii=False)
    print('written routes:', len(index))
    print('shape points raw -> simplified:', raw_pts, '->', simp_pts)


if __name__ == '__main__':
    main()
