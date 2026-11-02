"""Regression checks for publishing from a Git checkout and importing private inputs.

These tests use temporary directories only; they do not load an FPGA or contact GitHub.
"""
from pathlib import Path
import hashlib
import json
import os
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'build'))
import verify
import package
import import_dependencies as importer


def put(root,name,data=b'example'):
    path=root/name
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes(data)
    return path


def fixture(root):
    for name in verify.REQUIRED_DIRS:(root/name).mkdir()
    put(root,'README.md')
    put(root,'build/dependencies.json',json.dumps({
        'public_exclude':['build/local/','src/dependencies/private.c','board/hardware/','**/*.wdb'],
        'local_inputs':{},'source_paths':{}}).encode())


class CheckoutPackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='screwsort_package_test_')
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)/'checkout';self.root.mkdir()
        fixture(self.root)
        for module in (verify,package,importer):
            patcher=patch.object(module,'ROOT',self.root)
            patcher.start();self.addCleanup(patcher.stop)

    def names(self):
        return {p.relative_to(self.root).as_posix() for p in verify.release_files()}

    def test_git_directory_is_pruned_before_walk(self):
        put(self.root,'.git/objects/private',b'not for release')
        put(self.root,'.git/hooks/invalid.py',b'not python')
        walked=[];original=os.walk
        def recording(*args,**kwargs):
            for parent,dirs,files in original(*args,**kwargs):
                walked.append(Path(parent))
                yield parent,dirs,files
        with patch.object(verify.os,'walk',recording):names=self.names()
        self.assertFalse(any('.git' in p.relative_to(self.root).parts for p in walked))
        self.assertFalse(any('.git' in n.split('/') for n in names))
        self.assertEqual(verify.layout_errors(),[])
        self.assertNotIn('.git/objects/private',package.manifest()['files'])

    def test_worktree_git_file_is_accepted_but_never_packaged(self):
        put(self.root,'.git',b'gitdir: ../parent/.git/worktrees/release')
        self.assertEqual(verify.layout_errors(),[])
        self.assertNotIn('.git',self.names())
        self.assertNotIn('.git',package.manifest()['files'])

    def test_repository_support_files_are_manifested(self):
        for name in ('.gitignore','.gitattributes','LICENSE','CHANGELOG.md'):
            put(self.root,name)
            self.assertTrue(verify.valid_filename(name))
        self.assertEqual(verify.layout_errors(),[])
        self.assertTrue({'LICENSE','.gitignore','.gitattributes','CHANGELOG.md'}<=set(package.manifest()['files']))

    def test_unknown_top_level_file_fails_layout(self):
        put(self.root,'private-notes.txt')
        self.assertIn('Unexpected top-level item: private-notes.txt',verify.layout_errors())

    def test_missing_required_directory_fails_layout(self):
        (self.root/'skill').rmdir()
        self.assertIn('Required project directory missing: skill',verify.layout_errors())

    def test_generated_output_and_cache_are_excluded(self):
        for name in ('build/output/runtime.bin','sim/output/log.txt','board/output/frame.bmp',
                     'src/__pycache__/module.pyc','build/.Xil/state','src/.git/objects/private'):
            put(self.root,name)
            self.assertFalse(verify.selected(self.root/name))
        self.assertEqual(self.names(),{'README.md','build/dependencies.json'})

    def test_public_exclusions_apply_to_archive_contents(self):
        for name in ('build/local/bsp.a','src/dependencies/private.c',
                     'board/hardware/design.bit','sim/results/test.wdb'):
            put(self.root,name)
        put(self.root,'src/public.c')
        local=package.manifest(False);public=package.manifest(True)
        self.assertIn('src/dependencies/private.c',local['files'])
        self.assertEqual(set(public['files']),{'README.md','build/dependencies.json','src/public.c'})
        archive=package.write_archive(Path(self.temp.name)/'source.zip',public)
        with zipfile.ZipFile(archive) as z:
            self.assertIsNone(z.testzip())
            saved=json.loads(z.read('screwsort/build/release_manifest.json'))
            self.assertEqual(saved,public)
            self.assertEqual(set(z.namelist()),{'screwsort/'+n for n in public['files']}|{'screwsort/build/release_manifest.json'})
            for name,digest in public['files'].items():
                self.assertEqual(hashlib.sha256(z.read('screwsort/'+name)).hexdigest(),digest)
        with self.assertRaises(ValueError):package.write_archive(archive,public)

    def test_source_refresh_default_preserves_distribution(self):
        put(self.root,'build/release_manifest.json',json.dumps({'distribution':'source','files':{}}).encode())
        self.assertEqual(package.distribution_mode(),'source')
        self.assertEqual(package.distribution_mode('local'),'local')
        self.assertEqual(package.manifest(True)['distribution'],'source')
        self.assertNotIn('build/release_manifest.json',package.manifest(True)['files'])

    def test_refresh_does_not_bless_invalid_inputs(self):
        old={'distribution':'source','files':{}}
        path=put(self.root,'build/release_manifest.json',json.dumps(old).encode())
        with patch.object(sys,'argv',['package.py','--refresh']), \
             patch.object(package,'check',return_value={'status':'FAIL','errors':['bad input']}) as check:
            with self.assertRaises(SystemExit):package.main()
        self.assertEqual(json.loads(path.read_text()),old)
        check.assert_called_once_with(manifest=False,distribution='source')

    def test_source_refresh_uses_source_file_set(self):
        put(self.root,'build/release_manifest.json',json.dumps({'distribution':'source','files':{}}).encode())
        put(self.root,'build/local/private.a')
        with patch.object(sys,'argv',['package.py','--refresh']), \
             patch.object(package,'check',return_value={'status':'PASS'}):package.main()
        value=json.loads((self.root/'build/release_manifest.json').read_text())
        self.assertEqual(value['distribution'],'source')
        self.assertNotIn('build/local/private.a',value['files'])

    def test_public_file_inventory_refresh_preserves_metadata(self):
        path=put(self.root,'report/open_source_files.json',json.dumps({
            'schema_version':1,'version':'original-version','license_document':'report/licenses/third_party.md',
            'files':['stale/deleted.txt']}).encode())
        put(self.root,'src/new.c')
        put(self.root,'build/local/private.a')
        put(self.root,'.git/objects/private')
        package.refresh_public_file_list()
        result=json.loads(path.read_text())
        self.assertEqual(result['version'],'original-version')
        self.assertEqual(result['schema_version'],1)
        self.assertEqual(result['license_document'],'report/licenses/third_party.md')
        self.assertIn('report/open_source_files.json',result['files'])
        self.assertIn('src/new.c',result['files'])
        self.assertNotIn('stale/deleted.txt',result['files'])
        self.assertNotIn('build/local/private.a',result['files'])
        self.assertNotIn('build/release_manifest.json',result['files'])
        self.assertFalse(any('.git' in name.split('/') for name in result['files']))
        self.assertEqual(result['files'],sorted(package.manifest(True)['files']))
        before=path.read_bytes();package.refresh_public_file_list()
        self.assertEqual(path.read_bytes(),before)

    def test_manifest_hashes_refreshed_inventory(self):
        put(self.root,'build/release_manifest.json',json.dumps({'distribution':'source','files':{}}).encode())
        with patch.object(sys,'argv',['package.py','--refresh']), \
             patch.object(package,'check',return_value={'status':'PASS'}):package.main()
        value=json.loads((self.root/'build/release_manifest.json').read_text())
        inventory=self.root/'report/open_source_files.json'
        self.assertEqual(value['files']['report/open_source_files.json'],hashlib.sha256(inventory.read_bytes()).hexdigest())
        self.assertEqual(json.loads(inventory.read_text())['files'],sorted(value['files']))

    def test_archive_cannot_be_written_inside_checkout(self):
        with self.assertRaises(ValueError):
            package.write_archive(self.root/'build/public.zip',package.manifest(True))


class DependencyImportTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='screwsort_import_test_')
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)/'checkout';self.root.mkdir()
        self.release=Path(self.temp.name)/'release';self.release.mkdir()
        patcher=patch.object(importer,'ROOT',self.root)
        patcher.start();self.addCleanup(patcher.stop)
        self.inputs={'src/dependencies/private.c':b'original C', 'build/local/fsbl.elf':b'original ELF'}
        self.old={'src/dependencies/private.c':'software/private.c','build/local/fsbl.elf':'firmware/fsbl.elf'}
        self.config={'local_inputs':{n:hashlib.sha256(v).hexdigest() for n,v in self.inputs.items()},'source_paths':self.old}
        self.save_config()

    def save_config(self):
        put(self.root,'build/dependencies.json',json.dumps(self.config).encode())

    def source(self,legacy=False):
        for name,payload in self.inputs.items():put(self.release,self.old[name] if legacy else name,payload)

    def test_unified_layout_import_and_idempotence(self):
        self.source()
        self.assertEqual(importer.import_dependencies(self.release),{'verified':2,'imported':2,'already_present':0})
        for name,payload in self.inputs.items():self.assertEqual((self.root/name).read_bytes(),payload)
        self.assertEqual(importer.import_dependencies(self.release),{'verified':2,'imported':0,'already_present':2})

    def test_legacy_layout_import(self):
        self.source(legacy=True)
        self.assertEqual(importer.import_dependencies(self.release)['imported'],2)

    def test_missing_dependency_causes_no_partial_import(self):
        name,payload=next(iter(self.inputs.items()));put(self.release,name,payload)
        with self.assertRaisesRegex(ValueError,'Missing dependency'):
            importer.import_dependencies(self.release)
        self.assertFalse(any((self.root/n).exists() for n in self.inputs))

    def test_wrong_source_hash_causes_no_partial_import(self):
        self.source();put(self.release,'build/local/fsbl.elf',b'wrong version')
        with self.assertRaisesRegex(ValueError,'Different dependency'):
            importer.import_dependencies(self.release)
        self.assertFalse(any((self.root/n).exists() for n in self.inputs))

    def test_existing_different_dependency_is_not_overwritten(self):
        self.source();put(self.root,'build/local/fsbl.elf',b'local changes')
        with self.assertRaisesRegex(ValueError,'Refusing to replace'):
            importer.import_dependencies(self.release)
        self.assertEqual((self.root/'build/local/fsbl.elf').read_bytes(),b'local changes')
        self.assertFalse((self.root/'src/dependencies/private.c').exists())

    def test_outside_destination_rejected(self):
        self.config['local_inputs']={'../escaped':hashlib.sha256(b'data').hexdigest()}
        self.config['source_paths']={'../escaped':'somewhere'};self.save_config()
        with self.assertRaisesRegex(ValueError,'outside project'):
            importer.import_dependencies(self.release)
        self.assertFalse((self.root.parent/'escaped').exists())

    def test_outside_legacy_source_rejected(self):
        self.config['source_paths']['src/dependencies/private.c']='../escaped'
        self.save_config()
        with self.assertRaisesRegex(ValueError,'outside release'):
            importer.import_dependencies(self.release)
        self.assertFalse(any((self.root/n).exists() for n in self.inputs))


if __name__=='__main__':unittest.main()
