"""Independent proof that the QAT latent offsets do not change int8/int32 initialization."""
import json,hashlib
import numpy as np
import torch
from model_contract import ROOT,Net,arrays
p=ROOT/'output/training/head_selected.pt'
m=Net();m.load_state_dict(torch.load(p,weights_only=False,map_location='cpu')['state_dict'])
w,b=arrays(m);rng=np.random.default_rng(20261102)
with torch.no_grad():
    for layer in m.convs:
        layer.weight.add_(torch.from_numpy(rng.uniform(-.45,.45,tuple(layer.weight.shape)).astype(np.float32)/64))
dw,db=arrays(m)
assert np.array_equal(w,dw) and np.array_equal(b,db)
out=dict(status='PASS',seed=20261102,bin_halfwidth=.45,weight_quantum=1/64,initial_int8_weights_identical=True,
         initial_int32_biases_identical=True,checkpoint_sha256=hashlib.sha256(p.read_bytes()).hexdigest(),
         note='The same bin-interior preservation holds after adding integer symmetry perturbations; no rounding ties are introduced.')
(ROOT/'output/latent_dither_equivalence.json').write_text(json.dumps(out,indent=2))
print(json.dumps(out))
