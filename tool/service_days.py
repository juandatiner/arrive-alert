"""Which days a route runs, and between which hours, from the GTFS calendar.

TransMilenio publishes one `route_id` per direction *and* per slice of the
day: `MK86` is 04:30-21:03 under one id and 21:13-22:00 under another, and
both call themselves MK86. The app has to show one row per code per day, so
this module works out, for every route and every weekday, when it actually
runs - and then picks which of the same-code routes are worth keeping.
"""
import collections

DAYS = ('monday', 'tuesday', 'wednesday', 'thursday', 'friday',
        'saturday', 'sunday')

# A rival has to run for at least this long outside the hours already covered
# before it earns its own row. Below half an hour it is the same service with
# a slightly ragged published end time, not a bus the rider could catch.
UNIQUE_MINUTES = 30


def read_calendar(reader):
    """service_id -> tuple of 7 booleans, Monday first."""
    return {row['service_id']: tuple(row[d] == '1' for d in DAYS)
            for row in reader}


def to_minutes(hhmmss):
    """GTFS times pass midnight ("25:10:00"), which stays as 1510 here."""
    h, m, _ = hhmmss.split(':')
    return int(h) * 60 + int(m)


def windows_by_day(trip_route, trip_service, trip_start, calendar):
    """(route_id, weekday) -> (first minute, last minute, trips).

    The window is the first and last *departure from the route's first stop*,
    which is what a rider reads as "this bus runs from X to Y".
    """
    spans = {}
    for trip, start in trip_start.items():
        route = trip_route.get(trip)
        if route is None:
            continue
        running = calendar.get(trip_service[trip])
        if running is None:
            continue
        minute = to_minutes(start)
        for day, on in enumerate(running):
            if not on:
                continue
            key = (route, day)
            first, last, trips = spans.get(key, (minute, minute, 0))
            spans[key] = (min(first, minute), max(last, minute), trips + 1)
    return spans


def keep_by_day(spans, short_name_of):
    """Which routes survive each weekday, once same-code rivals are folded in.

    The busiest route under a code wins the day. A rival is only kept when it
    still carries riders in hours the winners do not: dropping it would take
    the first buses of the morning or the last of the night off the map,
    which is exactly when a rider needs to know the bus exists.
    """
    by_code_day = collections.defaultdict(list)
    for (route, day), (first, last, trips) in spans.items():
        by_code_day[(short_name_of[route], day)].append(
            (trips, first, last, route))

    kept = collections.defaultdict(set)   # route_id -> set of weekdays
    for (_, day), rivals in by_code_day.items():
        # Busiest first, so the winner is decided before anything is measured
        # against it, and ties fall to the longer service day.
        rivals.sort(key=lambda r: (-r[0], r[1] - r[2]))
        covered = []
        for trips, first, last, route in rivals:
            if not covered or _uncovered(first, last, covered) >= UNIQUE_MINUTES:
                kept[route].add(day)
                covered.append((first, last))
    return kept


def _uncovered(first, last, covered):
    """Minutes of [first, last] that no already-kept route is running."""
    minutes = last - first
    for other_first, other_last in covered:
        overlap = min(last, other_last) - max(first, other_first)
        if overlap > 0:
            minutes -= overlap
    return max(minutes, 0)


def pack(kept_days, spans, route):
    """The route's schedule as it ships: a weekday bitmask and, in day order,
    the `[first, last, trips]` of each day it is kept for."""
    days = sorted(kept_days)
    mask = 0
    for day in days:
        mask |= 1 << day
    return mask, [list(spans[(route, day)]) for day in days]
