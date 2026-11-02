"""Record recognition status, results, service metrics, and board environment."""
from pathlib import Path
import argparse,datetime,json,platform,subprocess,sys,time
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'src/python'))

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--seconds',type=float,default=60)
    p.add_argument('--label',default='recognition_only')
    a=p.parse_args()
    if a.seconds<=0:p.error('--seconds must be positive')
    import pynq
    from screwsortmint import ScrewSortMint
    now=datetime.datetime.now(datetime.timezone.utc)
    out=ROOT/'board/output'/now.strftime('%Y%m%d_%H%M%S');out.mkdir(parents=True,exist_ok=False)
    env=dict(captured_at=now.isoformat(),label=a.label,python=sys.version,platform=platform.platform(),
             pynq=getattr(pynq,'__version__','unknown'),motion_enabled=False,board_test='ACTUAL_RUN')
    try:env['gcc']=subprocess.check_output(['gcc','--version'],text=True).splitlines()[0]
    except (OSError,subprocess.CalledProcessError):env['gcc']='not_available'
    (out/'environment.json').write_text(json.dumps(env,ensure_ascii=False,indent=2),encoding='utf-8')
    app=ScrewSortMint(output_dir=out/'native')
    try:
        app.prepare().initialize().start();deadline=time.monotonic()+a.seconds
        with (out/'observations.jsonl').open('w',encoding='utf-8') as log:
            while time.monotonic()<deadline:
                item=dict(monotonic_ns=time.monotonic_ns(),status=app.status(),results=app.results(),metrics=app.metrics(),messages=app.messages())
                log.write(json.dumps(item,ensure_ascii=False)+'\n');log.flush()
                if item['metrics'].get('worker_error'):raise RuntimeError(item['metrics']['worker_error'])
                time.sleep(0.25)
        env['status']='COMPLETED'
    except BaseException as exc:
        env.update(status='FAILED',error=repr(exc));raise
    finally:
        try:app.close()
        except BaseException as exc:
            env.update(status='CLOSE_FAILED_BUFFERS_RETAINED',close_error=repr(exc));raise
        finally:(out/'environment.json').write_text(json.dumps(env,ensure_ascii=False,indent=2),encoding='utf-8')
    print(out)

if __name__=='__main__':main()
