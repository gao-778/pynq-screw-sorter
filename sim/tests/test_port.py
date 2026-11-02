"""Project source and interface utilities."""
from pathlib import Path
import ctypes as C,json,os,sys,tempfile,threading,unittest
from types import SimpleNamespace as NS
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'src/python'))
from screwsortmint.app import ScrewSortMint,validate_buffers,validate_mmio_metadata,REGIONS,SIZES,ABI,_pinned

class MetadataTests(unittest.TestCase):
    def overlay(self):
        import xml.etree.ElementTree as ET
        tree=ET.parse(ROOT/'board/hardware/screwsort.hwh')
        ip={};mem={}
        for node in tree.findall('.//MEMRANGE'):
            data=node.attrib
            address=int(data.get('BASEVALUE','0'),0)
            if address not in REGIONS:continue
            entry={'phys_addr':address,'addr_range':int(data['HIGHVALUE'],0)-address+1}
            (mem if data.get('MEMTYPE')=='MEMORY' else ip)[data['INSTANCE']]=entry
        return NS(ip_dict=ip,mem_dict=mem)
    def test_real_hwh_bram_memory_classification(self):
        o=self.overlay()
        self.assertNotIn(0x42000000,[e['phys_addr'] for e in o.ip_dict.values()])
        self.assertEqual(validate_mmio_metadata(o)[0x42000000],65536)
        self.assertEqual(validate_mmio_metadata(o)[0x43000000],65536)
    def test_missing_or_short_memory_is_still_rejected(self):
        for replacement in [None,{'phys_addr':0x42000000,'addr_range':4096}]:
            o=self.overlay();o.mem_dict.pop('recognition_registers')
            if replacement:o.mem_dict['recognition_registers']=replacement
            with self.assertRaisesRegex(RuntimeError,'0x42000000'):validate_mmio_metadata(o)
    def test_legacy_ip_only_metadata(self):
        o=self.overlay();o.ip_dict.update(o.mem_dict);del o.mem_dict
        self.assertEqual(validate_mmio_metadata(o)[0x42000000],65536)

class BufferTests(unittest.TestCase):
    def buffers(self):return [NS(device_address=a,nbytes=s) for a,s in zip([0x1000000,0x2000000,0x3000000],SIZES)]
    def test_valid(self):self.assertEqual(len(validate_buffers(self.buffers())),3)
    def test_overlap(self):
        b=self.buffers();b[1].device_address=b[0].device_address+64
        with self.assertRaises(ValueError):validate_buffers(b)
    def test_alignment_size_range_and_count(self):
        for attr,value in [('device_address',0x1000001),('device_address',0x1fffffc0),('nbytes',64)]:
            b=self.buffers();setattr(b[0],attr,value)
            with self.assertRaises(ValueError):validate_buffers(b)
        with self.assertRaises(ValueError):validate_buffers(self.buffers()+self.buffers())

class LifecycleTests(unittest.TestCase):
    def test_worker_fault_services_native_shutdown_without_freeing_buffers(self):
        app=ScrewSortMint();app._initialized=True;events=[]
        app._buffers=[NS(freebuffer=lambda:events.append('free'))]
        def fail():raise RuntimeError('device read failed')
        app._lib=NS(sl_service=fail,sl_command=lambda value:events.append(value),sl_shutdown=lambda:events.append('shutdown') or 0)
        app._loop()
        self.assertEqual(events,[b'STOP','shutdown']);self.assertFalse(app._initialized)
        self.assertIn('device read failed',app.status()['worker_error'])
        self.assertEqual(len(app._buffers),1)
    def test_sort_requests_use_new_native_api(self):
        app=ScrewSortMint();calls=[]
        app._lib=NS(sl_sort_all=lambda order:calls.append(('all',order)) or 0,
                    sl_auto=lambda cls,order:calls.append((cls,order)) or 0)
        app._dispatch('sort_all',1);app._dispatch('auto',(14,0))
        self.assertEqual(calls,[('all',1),(14,0)])
    def test_nut_auto_pick_is_rejected_before_queueing(self):
        app=ScrewSortMint()
        for cls in [15,16,17,'NUT_L','NUT_M','NUT_S']:
            with self.assertRaises(ValueError):app.auto_pick(cls)
        self.assertTrue(app._commands.empty())
    def test_status_includes_fresh_frame_gate_and_four_bins(self):
        app=ScrewSortMint();app._initialized=True
        def snapshot(out,capacity):
            data=[1,1,0,0,1,0,0,4,1,1,2,0,1,1,2,0,2,0,31,31,0,8,900,11667]
            for i,n in enumerate(data):out[i]=n
            return 0
        app._lib=NS(sl_state=snapshot)
        state=app.status()
        self.assertTrue(state['resume_waiting']);self.assertFalse(state['recognition_paused'])
        self.assertEqual(state['auto_state'],'wait_removal')
        self.assertEqual(state['bin_classes'],['M3_1','M3_5',None,None])
    def test_legacy_overlay_rejected_before_allocation(self):
        from unittest.mock import patch,Mock
        from screwsortmint.app import REGIONS
        with tempfile.TemporaryDirectory() as directory:
            bit=Path(directory)/'test.bit';bit.touch();bit.with_suffix('.hwh').touch()
            library=Path(directory)/'library.so';library.touch()
            overlay=NS(ip_dict={str(a):{'phys_addr':a,'addr_range':s} for a,s in REGIONS.items()})
            writes=[]
            class MMIO:
                def __init__(self,*args):pass
                def read(self,*args):return 0
                def write(self,*args):writes.append(args)
            allocate=Mock()
            pynq=NS(Overlay=lambda *a:overlay,MMIO=MMIO,allocate=allocate)
            fcntl=NS(LOCK_EX=1,LOCK_NB=2,flock=lambda *a:None)
            app=ScrewSortMint(bitfile=bit,library=library)
            with patch.dict(sys.modules,{'pynq':pynq,'fcntl':fcntl}),patch('builtins.open',return_value=NS(close=lambda:None)):
                with self.assertRaisesRegex(RuntimeError,'legacy fixed-DDR'):app.prepare()
            allocate.assert_not_called();self.assertEqual(writes,[]);self.assertTrue(app._closed)
    def app(self,drained=True):
        app=ScrewSortMint();app._closed=False
        class MMIO:
            def read(self,offset):return {0x9c:ABI,0xa8:3 if drained else 0,0x34:1}.get(offset,0)
            def write(self,*args):pass
        app._mmios={b:MMIO() for b in [0x42000000,0x40400000,0x40410000]}
        return app
    def test_free_only_after_drain(self):
        app=self.app();freed=[];app._buffers=[NS(freebuffer=lambda:freed.append(1))]
        app.close();self.assertEqual(freed,[1]);self.assertTrue(app._closed)
    def test_timeout_pins_allocation(self):
        from unittest.mock import patch
        app=self.app(False);freed=[];app._buffers=[NS(freebuffer=lambda:freed.append(1))]
        with patch('screwsortmint.app.time.monotonic',side_effect=[0,3]):
            with self.assertRaisesRegex(RuntimeError,'AXI/DMA'):app.close()
        self.assertEqual(freed,[]);self.assertIn(app,_pinned);_pinned.remove(app)
    def test_stop_preempts_urgent_work_and_discards_pick(self):
        app=ScrewSortMint();events=[];app._commands.put(('pick',None));app._cancel_motion.set()
        app._lib=NS(sl_command=lambda value:events.append(value),sl_service=lambda:events.append('service'),sl_urgent=lambda:1,sl_should_stop=lambda:1,
                    sl_shutdown=lambda:events.append('shutdown') or 0)
        app._loop();self.assertEqual(events,[b'STOP','service',b'STOP','shutdown']);self.assertTrue(app._commands.empty())

class NativeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        default=ROOT/'build/output/linux'/('screwlab_host.dll' if os.name=='nt' else 'libscrewlab.so')
        path=Path(os.environ.get('SCREWLAB_TEST_LIBRARY',default))
        cls.lib=C.CDLL(str(path))
        for name,args,result in [
            ('sl_map_register',[C.c_uint32,C.c_size_t,C.c_uint32],C.c_int),
            ('Xil_Out32',[C.c_size_t,C.c_uint32],None),('Xil_In32',[C.c_size_t],C.c_uint32),
            ('sl_bind_buffer',[C.c_uint,C.c_uint32,C.c_size_t,C.c_uint32],C.c_int),
            ('sl_phys_ptr',[C.c_uint32,C.c_size_t],C.c_void_p),
            ('sl_set_output_dir',[C.c_char_p],C.c_int),
            ('f_open',[C.c_void_p,C.c_char_p,C.c_uint],C.c_int),('f_close',[C.c_void_p],C.c_int),
            ('f_write',[C.c_void_p,C.c_void_p,C.c_uint,C.POINTER(C.c_uint)],C.c_int),
            ('sl_pick',[],C.c_int),('sl_direction',[C.c_uint],C.c_int),('sl_auto',[C.c_uint,C.c_uint],C.c_int)]:
            f=getattr(cls.lib,name);f.argtypes=args;f.restype=result
    def test_mmio_exact_mapping_and_faults(self):
        a=(C.c_uint32*8)();self.assertEqual(self.lib.sl_map_register(0x41200000,C.addressof(a),C.sizeof(a)),0)
        self.lib.Xil_Out32(0x41200004,0x12345678);self.assertEqual(a[1],0x12345678)
        self.assertEqual(self.lib.Xil_In32(0x41200004),0x12345678)
        self.assertNotEqual(self.lib.sl_map_register(0x41200004,C.addressof(a),4),0)
        self.assertEqual(self.lib.Xil_In32(0x41200001),0)
        self.assertEqual(self.lib.Xil_In32(0x41200020),0)
        self.assertEqual(C.c_int.in_dll(self.lib,'sl_mmio_fault').value,1)
    def test_physical_translation(self):
        b=(C.c_ubyte*SIZES[0])();address=0x1000000
        self.assertEqual(self.lib.sl_bind_buffer(0,address,C.addressof(b),len(b)),0)
        self.assertEqual(self.lib.sl_phys_ptr(address+100,200),C.addressof(b)+100)
        self.assertIsNone(self.lib.sl_phys_ptr(address+len(b)-1,2))
        self.assertNotEqual(self.lib.sl_bind_buffer(0,address+1,C.addressof(b),len(b)),0)
    def test_file_create_exclusive_and_traversal(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(self.lib.sl_set_output_dir(os.fsencode(directory)),0)
            f=C.c_void_p();self.assertEqual(self.lib.f_open(C.byref(f),b'0:/test.bin',6),0)
            data=C.create_string_buffer(b'PYNQ');n=C.c_uint()
            self.assertEqual(self.lib.f_write(C.byref(f),data,4,C.byref(n)),0)
            self.assertEqual(n.value,4);self.assertEqual(self.lib.f_close(C.byref(f)),0)
            self.assertEqual((Path(directory)/'test.bin').read_bytes(),b'PYNQ')
            self.assertEqual(self.lib.f_open(C.byref(f),b'0:/test.bin',6),8)
            self.assertEqual(self.lib.f_open(C.byref(f),b'0:/../bad.bin',6),7)
    def test_motion_disabled_before_hardware_access(self):
        self.assertEqual(self.lib.sl_pick(),-1);self.assertEqual(self.lib.sl_auto(0,0),-1)
        self.assertEqual(self.lib.sl_direction(0),-1)

if __name__=='__main__':unittest.main(verbosity=2)
