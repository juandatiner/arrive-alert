"""Checks the same-code folding keeps the services a rider could still catch.

Run from the repo root:  python3 tool/test_service_days.py
"""
import os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from service_days import keep_by_day, pack, to_minutes

MON = 0


def check(name, got, want):
    print(('ok  ' if got == want else 'FAIL') + '  ' + name)
    if got != want:
        print('       got: ', got)
        print('       want:', want)
    return got == want


def main():
    ok = True

    # MK86 on a Monday: the 04:30-21:03 service wins, and the 21:13-22:00 one
    # stays because nothing else is running then.
    spans = {
        ('13179', MON): (270, 1263, 276),
        ('13180', MON): (1273, 1320, 7),
    }
    kept = keep_by_day(spans, {'13179': 'MK86', '13180': 'MK86'})
    ok &= check('a late-night tail keeps its own row',
                sorted(kept), ['13179', '13180'])

    # M86 on a Sunday: three rivals all run inside the winner's hours.
    spans = {
        ('13182', MON): (270, 1202, 59),
        ('13185', MON): (390, 762, 43),
        ('13184', MON): (770, 820, 8),
        ('13186', MON): (342, 383, 5),
    }
    kept = keep_by_day(spans, {r: 'M86' for r in
                               ('13182', '13185', '13184', '13186')})
    ok &= check('services a busier sibling already covers are folded in',
                sorted(kept), ['13182'])

    # A rival that overlaps but runs 67 minutes past the winner is a real
    # last bus; one that overhangs by 5 minutes is a ragged end time.
    spans = {('a', MON): (551, 1403, 52), ('b', MON): (1123, 1470, 9)}
    kept = keep_by_day(spans, {'a': '6-4', 'b': '6-4'})
    ok &= check('an hour of service past the winner earns a row',
                sorted(kept), ['a', 'b'])

    spans = {('a', MON): (551, 1403, 52), ('b', MON): (1300, 1408, 9)}
    kept = keep_by_day(spans, {'a': '6-4', 'b': '6-4'})
    ok &= check('a five-minute overhang does not', sorted(kept), ['a'])

    # Different codes never compete, however few trips one of them runs.
    spans = {('a', MON): (270, 1263, 276), ('b', MON): (300, 900, 3)}
    kept = keep_by_day(spans, {'a': 'MK86', 'b': 'K86'})
    ok &= check('a different code is never folded away',
                sorted(kept), ['a', 'b'])

    # Packing: the windows line up with the set bits, in day order.
    spans = {('a', 4): (250, 1260, 125), ('a', 6): (250, 410, 18)}
    ok &= check('packing lists one window per day, in day order',
                pack({4, 6}, spans, 'a'),
                (1 << 4 | 1 << 6, [[250, 1260, 125], [250, 410, 18]]))

    ok &= check('a departure past midnight keeps counting up',
                to_minutes('24:30:00'), 1470)

    print('\nPASS' if ok else '\nFAIL')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
