"""Turns the 620MB TransMilenio GTFS feed into compact per-route assets.

Only one trip per route keeps its stops (the feed has exactly one shape per
route, so every trip of a route walks the same path), which is what collapses
stop_times.txt from 544MB to a few hundred KB. Every other trip is still read,
but only for its departure time - that is what the operating hours are built
from.
"""
import csv, json, math, os, shutil, sys, collections

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shape_snap import snap_stops
from service_days import read_calendar, windows_by_day, keep_by_day, pack

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
    # Wiped rather than merged: a rebuild drops routes a same-code sibling now
    # covers, and a leftover file for one of those ships a route the index no
    # longer lists.
    shutil.rmtree(f'{OUT}/routes', ignore_errors=True)
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

    calendar = read_calendar(csv.DictReader(open(f'{GTFS}/calendar.txt')))

    # One representative trip per route + its shape. Every trip of a kept
    # route is also remembered, because the operating hours come from all of
    # them, not just the representative one.
    trip_for_route, shape_for_route = {}, {}
    trip_route, trip_service = {}, {}
    for t in csv.DictReader(open(f'{GTFS}/trips.txt')):
        rid = t['route_id']
        if rid not in routes:
            continue
        trip_route[t['trip_id']] = rid
        trip_service[t['trip_id']] = t['service_id']
        if rid not in trip_for_route:
            trip_for_route[rid] = t['trip_id']
            shape_for_route[rid] = t['shape_id']
    wanted_trips = {tid: rid for rid, tid in trip_for_route.items()}
    print('trips:', len(trip_route), 'representative:', len(wanted_trips))

    stops = {}
    for s in csv.DictReader(open(f'{GTFS}/stops.txt')):
        stops[s['stop_id']] = (
            s['stop_name'].strip(),
            float(s['stop_lat']),
            float(s['stop_lon']),
        )
    print('stops:', len(stops))

    # Single streaming pass over the 544MB stop_times: the representative
    # trips give up their stop order, and every trip gives up the earliest
    # departure on it, which is when that trip leaves its first stop.
    seq_by_route = collections.defaultdict(list)
    trip_start = {}
    scanned = 0
    with open(f'{GTFS}/stop_times.txt', newline='') as fh:
        reader = csv.reader(fh)
        header = next(reader)
        i_trip = header.index('trip_id')
        i_departure = header.index('departure_time')
        i_stop = header.index('stop_id')
        i_seq = header.index('stop_sequence')
        for row in reader:
            scanned += 1
            tid = row[i_trip]
            if tid not in trip_route:
                continue
            # Times are zero-padded, so the earliest string is the earliest
            # departure - including the past-midnight "25:10:00" ones.
            departure = row[i_departure]
            current = trip_start.get(tid)
            if current is None or departure < current:
                trip_start[tid] = departure
            rid = wanted_trips.get(tid)
            if rid is not None:
                seq_by_route[rid].append((int(row[i_seq]), row[i_stop]))
    print('stop_times scanned:', scanned, 'routes with stops:', len(seq_by_route))

    spans = windows_by_day(trip_route, trip_service, trip_start, calendar)
    short_name_of = {rid: meta['short'] for rid, meta in routes.items()}
    kept_days = keep_by_day(spans, short_name_of)
    dropped = sum(1 for rid in routes if rid not in kept_days)
    print('route/day windows:', len(spans),
          '| routes a same-code rival covers entirely:', dropped)

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
        days = kept_days.get(rid)
        if not stop_list or not pts or not days:
            continue
        day_mask, hours = pack(days, spans, rid)

        shape = [(round(la, 5), round(lo, 5)) for la, lo in pts]
        # Precomputed so the app never has to guess where a stop sits on the
        # shape - see tool/shape_snap.py for why guessing goes wrong.
        stop_vertices, stop_meters = snap_stops(
            shape, [(s['lat'], s['lon']) for s in stop_list])
        json.dump(
            {
                'id': rid,
                'short': meta['short'],
                'long': meta['long'],
                'kind': meta['kind'],
                'color': meta['color'],
                'shape': [[la, lo] for la, lo in shape],
                'stops': stop_list,
                'si': stop_vertices,
                'sm': stop_meters,
                'd': day_mask,
                'h': hours,
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
            'd': day_mask,
            'h': hours,
        })

    json.dump(index, open(f'{OUT}/routes_index.json', 'w'),
              separators=(',', ':'), ensure_ascii=False)
    print('written routes:', len(index))
    print('shape points raw -> simplified:', raw_pts, '->', simp_pts)


if __name__ == '__main__':
    main()
