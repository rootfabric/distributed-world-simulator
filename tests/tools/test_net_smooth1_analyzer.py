import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[2]/'tools/net_smooth1/analyze_net_smooth1.py'
spec=importlib.util.spec_from_file_location('smooth_analyzer',MODULE)
analyzer=importlib.util.module_from_spec(spec);spec.loader.exec_module(analyzer)

class AnalysisTests(unittest.TestCase):
    def fixture(self, role='server', stall=False, missing_end=False, missing_events=False,
                move=True, bad_number=False, wrong_identity=False, nonmonotonic=False):
        events=[];n=0
        def emit(kind,data,t,measure=True):
            nonlocal n
            n+=1;events.append({'n':n,'t_us':t,'kind':kind,'data':data,'measure':measure})
        emit('header',{'schema':'dws.net_smooth.trace.v1','run_id':'wrong' if wrong_identity else 'run','role':role},0,False)
        emit('measure_start',{},1)
        for i in range(720):
            t=100+i*16667
            emit('frame',{'interval_ms':float('nan') if bad_number else (250 if stall and i==100 else 16.667)},t)
            if role=='server' and not missing_events:
                emit('server_loop',dict(tick=i,peers=2,rejections=0,process_ms=3,message_ms=1,
                     fixed_ms=1,snapshot_ms=.5,persistence_ms=.5,capture_ms=1,dropped_time_s=0),t+1)
            elif role!='server' and not missing_events:
                emit('client_loop',{'state':'CONNECTED','reconcile_failures':0},t+1)
                emit('remote_visual',{'id':'x','position':[i*.1 if move else 0,0,0],
                     'velocity':[6,0,0],'mode':'INTERPOLATE','yaw':0},t+2)
                if i%3==0:emit('snapshot_received',{'session':'one','tick':i},t+3)
        emit('measure_end',{},12000000)
        if nonmonotonic:events[-2]['t_us']=-1
        if not missing_end:events.append({'kind':'end','t_us':12000001,
                                         'data':{'produced':n,'written':n,'dropped':0,'io_errors':0}})
        return events
    def evaluate(self,**kwargs):
        role=kwargs.get('role','server')
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'trace.jsonl'
            path.write_text(''.join(json.dumps(x)+'\n' for x in self.fixture(**kwargs)))
            return analyzer.analyze_trace(path,role,'run')
    def test_healthy_server(self):self.assertEqual(self.evaluate()['verdict'],'PASS')
    def test_server_freeze_is_failure(self):self.assertEqual(self.evaluate(stall=True)['verdict'],'FAIL')
    def test_client_freeze_is_failure(self):self.assertEqual(self.evaluate(role='a',stall=True)['verdict'],'FAIL')
    def test_client_moves(self):self.assertEqual(self.evaluate(role='a')['verdict'],'PASS')
    def test_no_remote_movement_not_pass(self):self.assertEqual(self.evaluate(role='a',move=False)['verdict'],'INCONCLUSIVE')
    def test_missing_end_not_pass(self):self.assertEqual(self.evaluate(missing_end=True)['verdict'],'INCONCLUSIVE')
    def test_missing_events_not_pass(self):self.assertEqual(self.evaluate(missing_events=True)['verdict'],'INCONCLUSIVE')
    def test_bad_number_not_pass(self):self.assertEqual(self.evaluate(bad_number=True)['verdict'],'INCONCLUSIVE')
    def test_wrong_identity_not_pass(self):self.assertEqual(self.evaluate(wrong_identity=True)['verdict'],'INCONCLUSIVE')
    def test_clock_not_monotonic(self):self.assertEqual(self.evaluate(nonmonotonic=True)['verdict'],'INCONCLUSIVE')
    def test_missing_file_not_pass(self):
        self.assertEqual(analyzer.analyze_trace(Path('/not-a-file.trace'),'a','run')['verdict'],'INCONCLUSIVE')

if __name__=='__main__':unittest.main()
