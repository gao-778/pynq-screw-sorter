"""Manage Overlay loading, continuous memory, C service, and Python commands."""

from pathlib import Path
import atexit,ctypes as C,json,shutil,tempfile,threading,time,queue,os

ROOT=Path(__file__).resolve().parents[3]
CONTRACT=json.loads((ROOT/'board/overlay_contract.json').read_text(encoding='utf-8'))
ABI=int(CONTRACT['abi'],0)
REGIONS={int(item['base'],0):int(item['bytes']) for item in CONTRACT['regions']}
SIZES=tuple(CONTRACT['buffer_bytes'])
CLASS_NAMES=tuple(json.loads((ROOT/'data/model/classes.json').read_text(encoding='utf-8')))
AUTO_STATES=('off','browse','wait_target','moving','wait_removal','done','stopped','error','wait_start')
_pinned=[]  

def validate_mmio_metadata(overlay):

    by_address={}
    for table in (overlay.ip_dict,getattr(overlay,'mem_dict',{})):
        for entry in table.values():
            if 'phys_addr' not in entry:continue
            address=int(entry['phys_addr']);span=int(entry.get('addr_range') or 0)
            if span>by_address.get(address,0):by_address[address]=span
    for address,size in REGIONS.items():
        if by_address.get(address,0)<size:
            raise RuntimeError(f'HWH does not describe the expected MMIO region {address:#x} (requires {size:#x} bytes in ip_dict or mem_dict).')
    return by_address

def validate_buffers(buffers):
    if len(buffers)!=3:raise ValueError('Three independent buffers are required.')
    spans=[]
    for b,minimum in zip(buffers,SIZES):
        address=int(b.device_address);size=int(b.nbytes)
        if address<=0 or address&63 or size<minimum or address+size>int(CONTRACT['dma_address_limit'],0):
            raise ValueError('DMA buffers must be 64-byte aligned and within Zynq-7020 DDR.')
        for lo,hi in spans:
            if address<hi and lo<address+size:raise ValueError('DMA buffer allocations overlap.')
        spans.append((address,address+size))
    if len(spans)!=3:raise ValueError('Three independent buffers are required.')
    return spans

class ScrewSortMint:
    def __init__(self,bitfile=None,output_dir=None,library=None):
        self.bitfile=Path(bitfile or ROOT/'board/hardware/screwsort.bit').resolve()
        self.output_dir=Path(output_dir or ROOT/'board/output').resolve()
        self.library=Path(library or ROOT/'build/output/linux/libscrewlab.so').resolve()
        self._mutex=threading.RLock();self._stop=threading.Event();self._cancel_motion=threading.Event();self._commands=queue.SimpleQueue()
        self._thread=None;self._buffers=[];self._mmios={};self._lockfile=None;self._closed=True
        self._metrics={'service_calls':0,'max_service_gap_us':0,'worker_error':None}
        self._messages=[];self._initialized=False;self.overlay=None

    def prepare(self):

        if not self._closed:raise RuntimeError('This session is already prepared.')
        if hasattr(self,'_lib'):raise RuntimeError('Create a new ScrewSortMint instance for a new hardware session.')
        if not self.bitfile.is_file() or not self.bitfile.with_suffix('.hwh').is_file():
            raise FileNotFoundError('Build board/hardware/screwsort.bit and matching screwsort.hwh first.')
        if not self.library.is_file():raise FileNotFoundError('Run python build/build.py linux on the PYNQ board first.')
        from pynq import Overlay,MMIO,allocate
        import numpy as np
        import fcntl
        self._lockfile=open('/tmp/screwsortmint_pynq.lock','a+')
        try:fcntl.flock(self._lockfile,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except Exception:self._lockfile.close();self._lockfile=None;raise RuntimeError('Another ScrewSortMint session owns this overlay.')
        self._closed=False
        try:
            self.overlay=Overlay(str(self.bitfile))
            validate_mmio_metadata(self.overlay)
            for address,size in REGIONS.items():
                self._mmios[address]=MMIO(address,size)
            rec=self._mmios[0x42000000]
            if rec.read(0x9c)!=ABI:raise RuntimeError('This is the legacy fixed-DDR bitstream, not the migrated PYNQ overlay.')
            if rec.read(0)!=0x464e4554 or rec.read(0x38)!=0x4d433138 or rec.read(0x8c)!=12:
                raise RuntimeError('Recognition hardware/model capacity mismatch.')
            for size in SIZES:
                b=allocate(shape=(size,),dtype=np.uint8);self._buffers.append(b);b[:]=0;b.flush()
            validate_buffers(self._buffers)
            
            self._library_dir=tempfile.TemporaryDirectory(prefix='screwsortmint_native_')
            local=Path(self._library_dir.name)/self.library.name;shutil.copy2(self.library,local)
            self._lib=C.CDLL(str(local));self._bind_api()
            for address,mmio in self._mmios.items():
                if self._lib.sl_map_register(address,int(mmio.array.ctypes.data),int(mmio.array.nbytes)):
                    raise RuntimeError('Native MMIO registration failed.')
            for kind,b in enumerate(self._buffers):
                if self._lib.sl_bind_buffer(kind,int(b.device_address),int(b.ctypes.data),b.nbytes):
                    raise RuntimeError('Native DMA buffer registration failed.')
            self.output_dir.mkdir(parents=True,exist_ok=True)
            if self._lib.sl_set_output_dir(os.fsencode(self.output_dir)):raise RuntimeError('Output path is too long.')
            self._cache_callback=C.CFUNCTYPE(None,C.c_uint32,C.c_uint)(self._invalidate)
            self._lib.sl_set_cache_callback(self._cache_callback)
            rec.write(0x94,int(self._buffers[0].device_address));rec.write(0x98,int(self._buffers[1].device_address));rec.write(0xa0,1)
            if rec.read(0xa0)!=1 or rec.read(0x94)!=self._buffers[0].device_address or rec.read(0x98)!=self._buffers[1].device_address:
                raise RuntimeError('Dynamic DDR address configuration failed.')
            rec.write(0xa4,1)
            atexit.register(self.close)
            return self
        except Exception:
            self.close();raise

    def _bind_api(self):
        lib=self._lib
        specs={'sl_map_register':([C.c_uint32,C.c_size_t,C.c_uint32],C.c_int),
               'sl_bind_buffer':([C.c_uint,C.c_uint32,C.c_size_t,C.c_uint32],C.c_int),
               'sl_set_output_dir':([C.c_char_p],C.c_int),'sl_initialize':([],C.c_int),
               'sl_service':([],None),'sl_shutdown':([],C.c_int),'sl_urgent':([],C.c_int),
               'sl_should_stop':([],C.c_int),'sl_motion_enable':([C.c_int],C.c_int),
               'sl_command':([C.c_char_p],C.c_int),'sl_pick':([],C.c_int),
               'sl_direction':([C.c_uint],C.c_int),'sl_auto':([C.c_uint,C.c_uint],C.c_int),
               'sl_sort_all':([C.c_uint],C.c_int),'sl_state':([C.POINTER(C.c_uint),C.c_uint],C.c_int),
               'sl_target_count':([],C.c_uint),'sl_target':([C.c_uint,C.POINTER(C.c_double)],C.c_int),
               'sl_read_console':([C.c_void_p,C.c_uint],C.c_uint)}
        for name,(args,result) in specs.items():
            f=getattr(lib,name);f.argtypes=args;f.restype=result
        lib.sl_set_cache_callback.argtypes=[C.CFUNCTYPE(None,C.c_uint32,C.c_uint)]
        lib.sl_set_cache_callback.restype=None

    def _invalidate(self,address,bytes_count):
        for b in self._buffers:
            if int(b.device_address)<=address and address+bytes_count<=int(b.device_address)+b.nbytes:
                b.invalidate();return
        self._metrics['worker_error']='Cache invalidation requested outside owned buffers.'

    def initialize(self):

        if self._closed:self.prepare()
        if self._initialized:return self
        with self._mutex:
            status=self._lib.sl_initialize()
            self._drain_messages()
            if status:raise RuntimeError(f'Camera/application startup failed ({status}); inspect messages and run logs.')
            self._initialized=True
        return self

    def start(self):
        if not self._initialized:raise RuntimeError('Call initialize() before start().')
        if self._thread and self._thread.is_alive():return self
        if self._thread is not None:raise RuntimeError('The session worker stopped. Call close() and create a new ScrewSortMint instance.')
        self._stop.clear();self._thread=threading.Thread(target=self._loop,name='screwsortmint_service',daemon=True);self._thread.start();return self

    def _loop(self):
        previous=time.monotonic_ns()
        try:
            while not self._stop.is_set():
                now=time.monotonic_ns();gap=(now-previous)//1000;previous=now
                self._metrics['max_service_gap_us']=max(gap,self._metrics['max_service_gap_us'])
                with self._mutex:
                    if self._cancel_motion.is_set():
                        self._cancel_motion.clear()
                        
                        while not self._commands.empty():self._commands.get()
                        self._lib.sl_command(b'STOP')
                    
                    self._lib.sl_service();urgent=self._lib.sl_urgent()
                    if not urgent:
                        if not self._commands.empty():self._dispatch(*self._commands.get())
                        self._drain_messages()
                    stop=self._lib.sl_should_stop()
                self._metrics['service_calls']+=1
                if stop:break
                if not urgent:self._stop.wait(0.0005)
        except Exception as exc:self._metrics['worker_error']=repr(exc)
        finally:
            self._stop.set()
            
            with self._mutex:
                try:
                    self._lib.sl_command(b'STOP')
                    if self._lib.sl_shutdown():
                        self._metrics['worker_error']=self._metrics['worker_error'] or 'Native shutdown incomplete; call close() to retry. Buffers retained.'
                    else:self._initialized=False
                except Exception as exc:self._metrics['worker_error']=self._metrics['worker_error'] or repr(exc)

    def _drain_messages(self):
        buf=C.create_string_buffer(4096);n=self._lib.sl_read_console(buf,len(buf))
        if n:self._messages.append(buf.raw[:n].decode('utf-8',errors='replace'))

    def _dispatch(self,operation,value):
        if operation=='command':status=self._lib.sl_command(value.encode('ascii'))
        elif operation=='direction':status=self._lib.sl_direction(value)
        elif operation=='pick':status=self._lib.sl_pick()
        elif operation=='auto':status=self._lib.sl_auto(*value)
        elif operation=='sort_all':status=self._lib.sl_sort_all(value)
        else:raise ValueError(operation)
        if status:self._messages.append(f'{operation} request rejected: {status}\n')

    def _enqueue(self,operation,value=None):
        if not self._thread or not self._thread.is_alive():raise RuntimeError('The service worker is not running.')
        self._commands.put((operation,value))

    def select_direction(self,direction):

        self._enqueue('direction',{'left':1,'right':2,'up':3,'down':4}[direction])

    def enable_motion(self,enabled=True):
        if not self._initialized:raise RuntimeError('Initialize the camera and application first.')
        with self._mutex:
            if self._lib.sl_motion_enable(bool(enabled)):raise RuntimeError('Motion is currently busy.')

    def pick(self):self._enqueue('pick')
    def auto_pick(self,class_id,order='left_to_right'):
        if isinstance(class_id,str):class_id=CLASS_NAMES.index(class_id)
        if not 0<=class_id<15:raise ValueError('class_id is the model index 0..14, not the screen number.')
        self._enqueue('auto',(class_id,{'left_to_right':0,'top_to_bottom':1}[order]))
    def sort_all(self,order='left_to_right'):

        self._enqueue('sort_all',{'left_to_right':0,'top_to_bottom':1}[order])
    def stop(self):self.command('STOP')
    def command(self,text):
        if text not in ['ARM STOP','STOP','ARM STATUS','CAMERA STATUS','ARM LASTERROR','HELP']:raise ValueError('Unsupported command.')
        if text in ['STOP','ARM STOP']:
            if not self._thread or not self._thread.is_alive():raise RuntimeError('The service worker is not running.')
            self._cancel_motion.set();return
        self._enqueue('command',text)

    def results(self):
        if not self._initialized:return []
        result=[]
        with self._mutex:
            for i in range(self._lib.sl_target_count()):
                values=(C.c_double*10)()
                if self._lib.sl_target(i,values):continue
                class_id=int(values[0])
                result.append({'class_id':class_id,'class_name':CLASS_NAMES[class_id] if 0<=class_id<len(CLASS_NAMES) else 'UNKNOWN',
                               'pickable':0<=class_id<15,
                               'x_mm':values[1],'y_mm':values[2],'axis':list(values[3:5]),
                               'valid':bool(values[5]),'captured_ms':int(values[6]),
                               'screen_xy':list(values[7:9]),'axis_valid':bool(values[9])})
        return result

    def status(self):

        if not self._initialized:return {'initialized':False,'worker_running':bool(self._thread and self._thread.is_alive()),
                                         'worker_error':self._metrics['worker_error']}
        words=(C.c_uint*24)()
        with self._mutex:
            if self._lib.sl_state(words,len(words)):raise RuntimeError('Native state snapshot failed.')
        keys=('initialized','motion_enabled','arm_busy','recognition_paused','resume_waiting',
              'capture_active','inference_active','auto_state_id','auto_mode_id','auto_running',
              'queue_count','queue_index','actions_completed','removed_count','current_class_id',
              'current_bin','bin1_class_id','bin2_class_id','bin3_class_id','bin4_class_id',
              'coordinate_valid','coordinate_frame','coordinate_captured_ms','ui_fps_milli')
        state=dict(zip(keys,map(int,words)))
        for key in keys[:7]+('auto_running','coordinate_valid'):state[key]=bool(state[key])
        n=state['auto_state_id'];state['auto_state']=AUTO_STATES[n] if n<len(AUTO_STATES) else 'unknown'
        state['auto_mode']='sort_all' if state['auto_mode_id']==1 else 'class_pick'
        state['bin_classes']=[CLASS_NAMES[n] if n<len(CLASS_NAMES) else None for n in words[16:20]]
        state['worker_running']=bool(self._thread and self._thread.is_alive())
        state['worker_error']=self._metrics['worker_error']
        return state

    def messages(self):
        with self._mutex:items=self._messages[:];self._messages.clear()
        return ''.join(items)

    def metrics(self):return dict(self._metrics)

    def close(self):
        if self._closed:return
        self._stop.set()
        if self._thread and self._thread is not threading.current_thread():self._thread.join(timeout=5)
        if self._thread and self._thread.is_alive():
            _pinned.append(self);raise RuntimeError('Worker did not stop; DMA allocations retained.')
        with self._mutex:
            if hasattr(self,'_lib') and self._lib.sl_shutdown():
                _pinned.append(self);raise RuntimeError('Motion shutdown has not completed; buffers retained.')
            rec=self._mmios.get(0x42000000)
            if self._buffers and rec is not None and rec.read(0x9c)==ABI:
                rec.write(0x78,2);rec.write(4,8);rec.write(0xa4,0)
                for base in [0x40400000,0x40410000]:self._mmios[base].write(0x30,0)
                until=time.monotonic()+2
                while time.monotonic()<until:
                    halted=all(self._mmios[b].read(0x34)&1 for b in [0x40400000,0x40410000])
                    if rec.read(0xa8)&3==3 and not rec.read(8)&1 and halted:break
                    time.sleep(.001)
                else:
                    _pinned.append(self);raise RuntimeError('AXI/DMA has not drained; buffers retained. Resolve the drain or reboot the board before releasing this process.')
            for b in self._buffers:b.freebuffer()
            self._buffers.clear();self._initialized=False;self._closed=True
            while self in _pinned:_pinned.remove(self)
            if self._lockfile:self._lockfile.close();self._lockfile=None
        atexit.unregister(self.close)

    def __enter__(self):
        try:return self.initialize().start()
        except Exception:
            self.close();raise
    def __exit__(self,*exc):self.close()
