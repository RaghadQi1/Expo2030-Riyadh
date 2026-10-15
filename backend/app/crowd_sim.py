"""Expo indoor pedestrian *simulation*, NOT observations.

Physical geometry comes from the app's Swift graph export. Event times/capacities
come from the user's events.json. Unmeasured assumptions (width, attendance,
background visitor volume, comfortable pedestrian flow) are explicitly defined.

A 15-minute origin-destination assignment estimates bidirectional corridor flow;
a saturating speed/queuing function turns flow into simulated crossing time.
RandomForest learns this simulation rather than a hand-labelled hour->level rule.
"""
from __future__ import annotations
from functools import lru_cache
from pathlib import Path
import csv, heapq, json, math
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
EDGES_PATH = ROOT / 'data' / 'indoor_edges.csv'
EVENTS_PATH = ROOT / 'data' / 'events.json'
BOOTH_IDS = {'B013', 'B014', 'B015', 'B016'}
BASE_SPEED_M_PER_MIN = 78.0
WINDOW_MINUTES = 15
# Assumption: comfortable sustained bidirectional flow per metre of corridor width,
# not the maximum flow of real crowds (no actual corridor measurements available).
COMFORTABLE_PEOPLE_PER_MIN_PER_M = 1.25
FEATURES = ['hour', 'minute', 'day', 'floor', 'zone', 'length_m',
            'width_m', 'event_pressure', 'estimated_flow_15m', 'comfortable_capacity_15m']


def zone_for(x: float, y: float) -> int:
    if 300 <= x <= 455 and 310 <= y <= 450:
        return 3
    if x < 310:
        return 1
    if x > 455:
        return 2
    return 0


def assumed_width(edge: dict) -> float:
    """Designed conceptual widths in metres; NOT official pavilion dimensions."""
    names = edge['edge_id'].lower()
    if 'bypass' in names: return 2.5
    if 'center' in names or 'entrance' in names: return 3.2
    if 'east' in names or 'right' in names: return 1.7
    if 'west' in names or 'left' in names: return 2.3
    if 'lift' in names or 'walk406' in names: return 1.9
    if 'space/' in names: return 1.5
    return 2.4


@lru_cache(maxsize=1)
def graph_data():
    with EDGES_PATH.open(encoding='utf-8', newline='') as f:
        raw = list(csv.DictReader(f))
    edges, adjacency = {}, {}
    for row in raw:
        edge = dict(row)
        edge['floor'] = int(row['from_floor'])
        for name in ['from_x', 'from_y', 'to_x', 'to_y', 'length_m', 'transition_s']:
            edge[name] = float(row[name])
        edge['is_vertical'] = row['is_vertical'].strip().lower() == 'true'
        edge['width_m'] = assumed_width(edge)
        edge['mid_x'] = (edge['from_x'] + edge['to_x'])/2
        edge['mid_y'] = (edge['from_y'] + edge['to_y'])/2
        edge['zone'] = zone_for(edge['mid_x'], edge['mid_y'])
        edges[edge['edge_id']] = edge
        cost = edge['transition_s'] if edge['is_vertical'] else max(.01, edge['length_m'])
        adjacency.setdefault(edge['from_node'], []).append((edge['to_node'], edge['edge_id'], cost))
        adjacency.setdefault(edge['to_node'], []).append((edge['from_node'], edge['edge_id'], cost))
    return edges, adjacency


@lru_cache(maxsize=1)
def events():
    return [e for e in json.loads(EVENTS_PATH.read_text(encoding='utf-8'))
            if e.get('booth_id') in BOOTH_IDS]


@lru_cache(maxsize=150)
def path_between(src: str, dst: str):
    if src == dst: return ()
    edges, adj = graph_data()
    q = [(0.0, src)]
    dist = {src: 0.0}
    pred = {}
    while q:
        cost, node = heapq.heappop(q)
        if cost > dist[node] + 1e-8: continue
        if node == dst: break
        for nxt, key, length in adj.get(node, []):
            alt = cost + length
            if alt < dist.get(nxt, math.inf) - 1e-9:
                dist[nxt] = alt
                pred[nxt] = (node, key)
                heapq.heappush(q, (alt, nxt))
    if dst not in pred: raise ValueError(f'No indoor route from {src} to {dst}')
    used = []
    node = dst
    while node != src:
        node, edge_id = pred[node]
        used.append(edge_id)
    return tuple(reversed(used))


def _gaussian_mass(now_minutes, centre_minutes, sigma):
    # 15-minute bucket approximation to a normalized temporal arrival pulse.
    z = (now_minutes - centre_minutes) / sigma
    return WINDOW_MINUTES * math.exp(-0.5*z*z) / (sigma*math.sqrt(2*math.pi))


def demand_estimate(hour: int, minute: int, day: int,
                    attendance_scale: float = 1.0,
                    background_scale: float = 1.0,
                    events_override=None):
    """Return estimated bidirectional arrivals per edge per 15 minutes.

    Routes follow the same conceptual Swift indoor corridors. Counts are NOT
    sensor observations. Assumed attendance and background can be varied in
    separate simulated days to create held-out scenarios.
    """
    edges, _ = graph_data()
    flow = {key: 0.0 for key in edges}
    pressure = {key: 0.0 for key in edges}
    t = hour*60 + minute
    weekend = 1.18 if day in (5, 6) else 1.0  # Friday and Saturday
    for event in events_override if events_override is not None else events():
        booth = event['booth_id']
        if booth not in BOOTH_IDS: continue
        start = 60*int(event['start_time'][:2]) + int(event['start_time'][3:])
        end = 60*int(event['end_time'][:2]) + int(event['end_time'][3:])
        attendees = event['capacity'] * 0.76 * attendance_scale * weekend
        arrivals = attendees * _gaussian_mass(t, start - 12, 23)
        departures = attendees * _gaussian_mass(t, end + 8, 11)
        # Every attendee starts at the entrance; exit is also an entrance node
        # for this simulated journey. Floor changes use the modelled lift.
        route = path_between('f1/entrance', 'space/'+booth)
        for key in route:
            flow[key] += arrivals + departures
            pressure[key] += arrivals + departures
    # Ambient wandering not tied to a scheduled event (assumption, not measured).
    hour_profile = 0.4 + 0.5*math.exp(-0.5*((t-12*60)/170)**2) + 0.60*math.exp(-0.5*((t-18*60)/140)**2)
    visitors = (18.0 * hour_profile * background_scale * weekend)
    paths = [('f1/entrance', 'space/cafe', 0.25),
             ('f1/entrance', 'space/stage', 0.20),
             ('f1/entrance', 'space/wc', 0.15),
             ('f1/entrance', 'space/B013', 0.12),
             ('f1/entrance', 'space/B014', 0.12),
             ('f1/entrance', 'space/B015', 0.08),
             ('f1/entrance', 'space/B016', 0.08)]
    for src, dest, share in paths:
        for key in path_between(src, dest):
            flow[key] += visitors * share
    return flow, pressure


def feature_rows(hour, minute, day, attendance_scale=1.0, background_scale=1.0, events_override=None):
    flow, pressure = demand_estimate(hour, minute, day, attendance_scale, background_scale, events_override)
    edges, _ = graph_data()
    result = []
    for key, edge in edges.items():
        if edge['is_vertical'] or edge['length_m'] <= 0.01: continue
        cap = edge['width_m'] * COMFORTABLE_PEOPLE_PER_MIN_PER_M * WINDOW_MINUTES
        result.append({
            'edge_id': key, 'hour': hour, 'minute': minute, 'day': day,
            'floor': edge['floor'], 'zone': edge['zone'],
            'length_m': round(edge['length_m'], 3), 'width_m': edge['width_m'],
            'event_pressure': round(pressure[key], 4),
            'estimated_flow_15m': round(flow[key], 4),
            'comfortable_capacity_15m': round(cap, 4),
        })
    return result


def simulated_passage_factor(row: dict, rng):
    """Pedestrian slowdown assumption using load/capacity & random variation.

    Independent of 'hour' or 'zone' class thresholds: simulation assigns event
    travelers to real graph links; crowd load then causes passage delay. This is
    a *conceptual* queue/speed proxy, NOT calibrated crowd physics.
    """
    actual_demand = max(0.0, row['estimated_flow_15m'] * rng.lognormal(0, 0.18))
    saturation = actual_demand/max(1, row['comfortable_capacity_15m'])
    slowdown = 1 + 1.45*max(0, saturation-0.30)**1.45
    # Unmodelled interpersonal variability in walking speed / blockage.
    slowdown *= rng.lognormal(0, 0.035)
    return round(float(np.clip(slowdown, 1.0, 4.25)), 4)


def make_dataset(n=20_000, seed=2030):
    rng = np.random.default_rng(seed)
    rows = []
    scenario_id = 0
    while len(rows) < n:
        hour = int(rng.integers(9, 22))
        minute = int(rng.choice([0, 15, 30, 45]))
        day = int(rng.integers(0, 7))
        attendance_scale = float(rng.uniform(.55, 1.65))
        background_scale = float(rng.uniform(.65, 1.55))
        # Group all edges in one simulated instant. Split by scenario_id later
        # to avoid training on edges from exactly the same scenario as testing.
        scenario = feature_rows(hour, minute, day, attendance_scale, background_scale)
        for row in scenario:
            row['scenario_id'] = scenario_id
            row['assumed_attendance_scale'] = round(attendance_scale, 4)
            row['assumed_background_scale'] = round(background_scale, 4)
            row['time_factor_target'] = simulated_passage_factor(row, rng)
            row['travel_seconds_target'] = round(row['length_m'] / BASE_SPEED_M_PER_MIN * 60 * row['time_factor_target'], 4)
            rows.append(row)
        scenario_id += 1
    # We stop at an exact, deterministic number of samples; entire scenarios
    # never split across train/test even when the last scenario is truncated.
    return pd.DataFrame(rows[:n])
