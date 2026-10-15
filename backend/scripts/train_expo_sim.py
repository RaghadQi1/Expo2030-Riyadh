"""Train and honestly evaluate simulated corridor time multipliers.

Usage from backend/: python scripts/train_expo_sim.py
"""
import json, sys
from pathlib import Path
import numpy as np
import joblib
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import GroupShuffleSplit
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from app.crowd_sim import make_dataset, FEATURES, graph_data, BASE_SPEED_M_PER_MIN

out = ROOT / 'models'
out.mkdir(exist_ok=True)
frame = make_dataset()
frame.to_csv(ROOT/'data'/'expo_specific_training_20000.csv', index=False)
train_idx, test_idx = next(GroupShuffleSplit(n_splits=1, test_size=.2, random_state=2030).split(frame, groups=frame['scenario_id']))
train, test = frame.iloc[train_idx], frame.iloc[test_idx]
assert not set(train.scenario_id).intersection(set(test.scenario_id))
model = RandomForestRegressor(n_estimators=160, max_depth=15, min_samples_leaf=3, max_features=.85,
                              n_jobs=-1, random_state=2030)
model.fit(train[FEATURES], train.time_factor_target)
pred = np.clip(model.predict(test[FEATURES]), 1, 4.25)
actual = test.time_factor_target.to_numpy()
naive = np.ones_like(actual)
median = np.full_like(actual, np.median(train.time_factor_target))
metric = lambda p: {'mae':round(float(mean_absolute_error(actual,p)),5),
                    'rmse':round(float(np.sqrt(mean_squared_error(actual,p))),5)}
report = {
 'source':'EXPO_SPECIFIC_SYNTHETIC_CORRIDOR_SIMULATION',
 'provenance':'events.json + saudi-pavilion-indoor.json + exported Swift indoor_edges.csv',
 'is_real_visitor_data':False,
 'target':'simulated per-corridor travel-time multiplier (regression)',
 'training_rows':int(len(train)), 'test_rows':int(len(test)),
 'train_scenarios':int(train.scenario_id.nunique()), 'test_scenarios':int(test.scenario_id.nunique()),
 'split':'GroupShuffleSplit by scenario_id; no same scenario in both sets',
 'features':FEATURES,
 'metrics':{'random_forest':{**metric(pred),'r2':round(float(r2_score(actual,pred)),5)},
            'no_crowd_baseline':metric(naive), 'train_median_baseline':metric(median)},
 'assumptions':[
    'Event schedules and capacities are fictional dataset records, assumed repeated daily',
    'Attendance factors and general visitors are simulated; no real counts',
    'Corridor widths are design assumptions (not surveyed physical measurements)',
    'Comfortable bidirectional flow assumed to be 1.25 persons/minute/metre',
    'Delay multiplier is from load/comfortable capacity plus stochastic variability',
    'Reported accuracy is on held-out simulator scenarios, NOT measured Expo crowd data',
 ],
 'route_calibration_warning':'Ground-truth travel time at Expo requires measurements. Do not describe predicted ETA as real.'}
joblib.dump({'model':model,'features':FEATURES,'simulation':True,'training_source':report['source']}, out/'expo_simulated_crowd_rf.joblib', compress=3)
(out/'evaluation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(report, ensure_ascii=False, indent=2))
