"""Serve Expo-specific *simulated* pedestrian flow predictions.

Loads a previously trained RandomForestRegressor; it never uses Melbourne's
sensor model and never claims observed Expo crowd densities. Swift uses the
per-edge multiplier with its own physical walkable graph + Dijkstra.
"""
from functools import lru_cache
from pathlib import Path
import math
import numpy as np
import pandas as pd
import joblib
from .crowd_sim import FEATURES, feature_rows, graph_data, zone_for

MODEL_PATH = Path(__file__).resolve().parents[1] / 'models' / 'expo_simulated_crowd_rf.joblib'
LEVEL_AR = {0:'خفيفة', 1:'متوسطة', 2:'عالية'}


@lru_cache(maxsize=1)
def model():
    if not MODEL_PATH.is_file():
        raise RuntimeError('Missing trained model. From backend/ run: python scripts/train_expo_sim.py')
    payload = joblib.load(MODEL_PATH)  # The artifact ships from our training script, not a user upload.
    assert payload['features'] == FEATURES and payload['simulation'] is True
    return payload['model']


def _level(factor):
    return 0 if factor < 1.12 else (1 if factor < 1.55 else 2)


def _round_factor(value):
    return round(float(np.clip(value, 1.0, 4.25)), 4)


def all_edge_predictions(hour: int, day: int, minute: int = 0, events_override=None):
    """Predict on graph-aligned scheduled footfall; no live visitor counts."""
    rows = feature_rows(hour, minute, day, events_override=events_override)
    frame = pd.DataFrame(rows)
    factors = model().predict(frame[FEATURES])
    result = {}
    for row, factor in zip(rows, factors):
        factor = _round_factor(factor)
        level = _level(factor)
        result[row['edge_id']] = {
            'edge_id':row['edge_id'], 'floor':row['floor'], 'zone':row['zone'],
            'level':level, 'label_ar':LEVEL_AR[level], 'time_factor':factor,
            'event_pressure':round(row['event_pressure'],2),
            'estimated_flow_15m':round(row['estimated_flow_15m'],2),
            'assumed_width_m':row['width_m'],
        }
    return result


def predict(hour: int, day: int, zone: int, floor: int=1, events_override=None):
    relevant = [p for p in all_edge_predictions(hour, day, events_override=events_override).values()
                if p['zone']==zone and p['floor']==floor]
    factor = _round_factor(np.mean([p['time_factor'] for p in relevant]) if relevant else 1.0)
    level = _level(factor)
    return {'level':level,'label_ar':LEVEL_AR[level], 'time_factor':factor,
            'simulation':True,'hour':hour,'day':day,'zone':zone,'floor':floor,
            'event_pressure':round(sum(p['event_pressure'] for p in relevant)/len(relevant),2) if relevant else 0.0,
            'training_source':'EXPO_SPECIFIC_SYNTHETIC_CORRIDOR_SIMULATION'}


def indoor_zone(x, y, floor=1):
    return zone_for(x, y)


def predict_edge_request(request, events_override=None):
    pred = all_edge_predictions(request.hour, request.day, events_override=events_override)
    edges, _ = graph_data()
    out = []
    for item in request.edges:
        if item.edge_id in pred:
            result = dict(pred[item.edge_id])
        elif item.edge_id in edges:  # zero-distance room/door, no walking delay
            e = edges[item.edge_id]
            result = {'floor':e['floor'],'zone':e['zone'],'level':0,
                      'label_ar':LEVEL_AR[0],'time_factor':1.0,'event_pressure':0.0,
                      'estimated_flow_15m':0.0,'assumed_width_m':e['width_m']}
        else:
            # Legacy/external caller: use nearest real corridor on same floor,
            # but this does NOT insert an invented corridor into the graph.
            options = [e for e in edges.values() if not e['is_vertical']
                       and e['length_m']>0 and e['floor']==item.floor]
            closest = min(options, key=lambda e:(e['mid_x']-item.x)**2+(e['mid_y']-item.y)**2)
            result = dict(pred[closest['edge_id']])
        result['edge_id'] = item.edge_id
        result['floor'] = item.floor
        out.append(result)
    return out
