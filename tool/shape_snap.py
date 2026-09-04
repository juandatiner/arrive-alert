"""Placing stops along a route's drawn shape.

Two things go wrong with the obvious "snap each stop to its nearest shape
vertex":

  * the shapes are simplified down to ~2 vertices per stop, so two stops
    blocks apart routinely land on the same vertex and measure 0 m between
    them;
  * routes that run the same corridor twice (most zonal loops) send a stop
    on the return leg back onto the outbound vertex.

Projecting onto the nearest *segment* fixes the resolution, and walking the
shape forward inside a limited lookahead window fixes the loops - a plain
forward argmin still jumps to the far end of a loop, because the terminal
sits at both ends of the shape.
"""
import math

EARTH_R = 6371000.0


def _projector(shape):
    """Local flat projection - a city fits in it with centimetre error."""
    lat0 = math.radians(sum(p[0] for p in shape) / len(shape))
    kx = math.cos(lat0) * math.pi / 180 * EARTH_R
    ky = math.pi / 180 * EARTH_R
    return lambda lat, lon: (lon * kx, lat * ky)


# How far ahead of the last stop to look for the next one. Comfortably more
# than the longest gap between consecutive stops on any bundled route, and
# far less than the length of a loop.
LOOKAHEAD_METERS = 4000.0

# A stop further than this from every segment in the window is not on the
# corridor the window covers.
OFF_SHAPE_METERS = 400.0

# Two segments this close in fit are the same place on the ground; prefer the
# earlier one.
TIE_METERS = 30.0


def snap_stops(shape, stops):
    """(vertex index, metres along the shape) for each stop, both monotone.

    `shape` is [(lat, lon), ...]; `stops` is [(lat, lon), ...] in ride order.
    The vertex index is what to draw with; the metres are what to measure
    with.
    """
    if len(shape) < 2 or not stops:
        return [0] * len(stops), [0] * len(stops)

    project = _projector(shape)
    xy = [project(lat, lon) for lat, lon in shape]
    cumulative = [0.0]
    for i in range(1, len(xy)):
        cumulative.append(cumulative[-1] + math.dist(xy[i - 1], xy[i]))

    def project_onto(segment, point):
        (ax, ay), (bx, by) = xy[segment], xy[segment + 1]
        dx, dy = bx - ax, by - ay
        length_sq = dx * dx + dy * dy
        t = 0.0 if length_sq == 0 else max(
            0.0, min(1.0, ((point[0] - ax) * dx + (point[1] - ay) * dy) / length_sq))
        return t, math.dist(point, (ax + t * dx, ay + t * dy))

    def best_in(point, first, last):
        best = (float('inf'), first, 0.0)
        for i in range(first, last):
            t, d = project_onto(i, point)
            if d < best[0]:
                best = (d, i, t)
        return best

    indices, meters = [], []
    segment_count = len(xy) - 1
    cursor = 0
    travelled = 0.0
    for order, (lat, lon) in enumerate(stops):
        point = project(lat, lon)
        if order == 0:
            # The shape of a loop route passes its own terminal twice, so the
            # closest segment to the first stop can be the last one. Take the
            # earliest segment that is as good as the closest, not the best.
            closest, _, _ = best_in(point, 0, segment_count)
            distance, segment, t = next(
                (d, i, tt)
                for d, i, tt in (
                    (project_onto(i, point)[1], i, project_onto(i, point)[0])
                    for i in range(segment_count)
                )
                if d <= closest + TIE_METERS
            )
        else:
            last = cursor
            while (last + 1 < segment_count
                   and cumulative[last + 1] - cumulative[cursor] < LOOKAHEAD_METERS):
                last += 1
            distance, segment, t = best_in(point, cursor, last + 1)
            # Nothing plausible ahead: the stop is off the drawn corridor (or
            # the shape skips it), so fall back to the rest of the route.
            if distance > OFF_SHAPE_METERS:
                distance, segment, t = best_in(point, cursor, segment_count)

        along = cumulative[segment] + t * (
            cumulative[segment + 1] - cumulative[segment])
        # Never let a later stop measure as earlier than the one before it.
        travelled = max(travelled, along)
        meters.append(round(travelled))
        indices.append(segment + (1 if t >= 0.5 else 0))
        cursor = segment

    return indices, meters
