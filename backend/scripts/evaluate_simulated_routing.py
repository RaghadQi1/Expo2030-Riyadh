"""Compare distance-only versus AI-weighted routing against held-out *simulated* delays.

No real visitor observations, no claim of real travel time savings.
Run from backend/: python scripts/evaluate_simulated_routing.py
"""
from pathlib import Path
import heapq, json, sys
import joblib
import numpy as np
import pandas as pd
from sklearn.model_selection import GroupShuffleSplit

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from app.crowd_sim import graph_data, FEATURES, BASE_SPEED_M_PER_MIN

frame = pd.read_csv(ROOT/'data'/'expo_specific_training_20000.csv')
train_ids, test_ids = next(GroupShuffleSplit(n_splits=1,test_size=.2,random_state=2030).split(frame,groups=frame['scenario_id']))
test = frame.iloc[test_ids].copy()
assert set(frame.iloc[train_ids].scenario_id).isdisjoint(set(test.scenario_id))
artifact = joblib.load(ROOT/'models'/'expo_simulated_crowd_rf.joblib')
test['predicted'] = np.clip(artifact['model'].predict(test[FEATURES]),1,4.25)
edges, adj=graph_data()
valid = {x['edge_id'] for x in frame.iloc[0:len([e for e in edges.values() if not e['is_vertical'] and e['length_m']>0])].to_dict('records')}
origin='f1/entrance'
targets = ['space/B013','space/B014','space/B015','space/B016']

def path(dst, factors=None):
    factors = factors or {}
    q=[(0.0,origin)]
    best={origin:0.0}
    previous={}
    while q:
        score,node=heapq.heappop(q)
        if score>best[node]+1e-8:continue
        if node==dst:break
        for nxt, key, _ in adj[node]:
            edge=edges[key]
            cost = edge['transition_s'] if edge['is_vertical'] else edge['length_m']/BASE_SPEED_M_PER_MIN*60*factors.get(key,1.0)
            trial=score+cost
            if trial<best.get(nxt,float('inf'))-1e-9:
                best[nxt]=trial
                previous[nxt]=(node,key)
                heapq.heappush(q,(trial,nxt))
    if dst not in best:raise ValueError(dst)
    taken=[]
    at=dst
    while at!=origin:
        at,key=previous[at]
        taken.append(key)
    return tuple(reversed(taken))

def actual_cost(paths, true_factors):
    return sum(edges[key]['transition_s'] if edges[key]['is_vertical'] else
               edges[key]['length_m']/BASE_SPEED_M_PER_MIN*60*true_factors.get(key,1)
               for key in paths)

records=[]
for scenario, group in test.groupby('scenario_id'):
    # Ignore the truncated last scenario; every held-out evaluation here has a full edge set.
    if not valid.issubset(set(group.edge_id)):continue
    true=dict(zip(group.edge_id,group.time_factor_target))
    predicted=dict(zip(group.edge_id,group.predicted))
    for dest in targets:
        p0=path(dest)
        p1=path(dest,predicted)
        t0=actual_cost(p0,true)
        t1=actual_cost(p1,true)
        records.append({'scenario_id':int(scenario),'destination':dest,
                        'distance_only_actual_s':round(t0,3),
                        'predicted_route_actual_s':round(t1,3),
                        'saved_simulated_s':round(t0-t1,3),
                        'geometry_changed':p0!=p1})
results=pd.DataFrame(records)
results.to_csv(ROOT/'models'/'heldout_routing_comparison.csv',index=False)
changed=results[results.geometry_changed]
summary={'evaluation_type':'held-out simulated travel times, not real measured ETA',
         'evaluated_journeys':len(results),
         'changed_route_journeys':len(changed),
         'mean_simulated_seconds_saved_all':round(float(results.saved_simulated_s.mean()),4),
         'mean_simulated_seconds_saved_when_changed':round(float(changed.saved_simulated_s.mean()),4) if len(changed) else 0,
         'fraction_with_improved_time':round(float((results.saved_simulated_s>1e-5).mean()),4),
         'fraction_with_worse_time':round(float((results.saved_simulated_s<-1e-5).mean()),4)}
(ROOT/'models'/'routing_evaluation.json').write_text(json.dumps(summary,indent=2),encoding='utf8')
print(json.dumps(summary,indent=2))
