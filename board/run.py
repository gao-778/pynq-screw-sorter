"""Run a PYNQ application session with explicitly selected motion control."""
from pathlib import Path
import argparse,json,sys,time
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'src/python'))

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--seconds',type=float,default=30)
    p.add_argument('--enable-motion',action='store_true')
    p.add_argument('--sort-all',action='store_true')
    a=p.parse_args()
    if a.seconds<=0:p.error('--seconds must be positive')
    if a.sort_all and not a.enable_motion:p.error('--sort-all requires --enable-motion')
    from screwsortmint import ScrewSortMint
    app=ScrewSortMint()
    try:
        app.prepare().initialize().start()
        if a.enable_motion:app.enable_motion()
        if a.sort_all:app.sort_all()
        deadline=time.monotonic()+a.seconds
        while time.monotonic()<deadline:
            print(json.dumps({'status':app.status(),'results':app.results(),'metrics':app.metrics()},ensure_ascii=False),flush=True)
            messages=app.messages()
            if messages:print(messages,flush=True)
            if app.metrics().get('worker_error'):raise RuntimeError(app.metrics()['worker_error'])
            time.sleep(1)
    except KeyboardInterrupt:pass
    finally:app.close()

if __name__=='__main__':main()
