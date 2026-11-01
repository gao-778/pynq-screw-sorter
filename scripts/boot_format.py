"""Bounded ELF32 and Zynq Bootgen partition checks; no tool or hardware access."""
import hashlib
import struct
from project_common import require


def bit_payload(data):
    require(len(data)>=4, 'Truncated bit header')
    pos=2+int.from_bytes(data[:2],'big')
    require(data[pos:pos+2]==b'\0\1', 'Unexpected bit header marker')
    pos+=2
    while pos<len(data):
        key=data[pos:pos+1];pos+=1
        if key==b'e':
            require(pos+4<=len(data), 'Truncated bit size')
            size=int.from_bytes(data[pos:pos+4],'big');pos+=4
            require(size>0 and pos+size==len(data) and size%4==0, 'Invalid bitstream payload size')
            return data[pos:]
        require(key in (b'a',b'b',b'c',b'd') and pos+2<=len(data), 'Unexpected bit field')
        size=int.from_bytes(data[pos:pos+2],'big');pos+=2+size
        require(pos<=len(data), 'Truncated bit field')
    raise RuntimeError('Missing bit payload')


def loads(data):
    require(len(data)>=52 and data[:7]==b'\x7fELF\x01\x01\x01', 'Expected little-endian ELF32')
    require(struct.unpack_from('<H',data,18)[0]==40, 'Expected ARM ELF machine')
    offset=struct.unpack_from('<I',data,28)[0]
    size,count=struct.unpack_from('<HH',data,42)
    require(size>=32 and count>0 and offset+size*count<=len(data), 'Invalid program headers')
    segments=[]
    for index in range(count):
        row=struct.unpack_from('<8I',data,offset+index*size)
        if row[0]==1 and row[4]:
            require(row[1]+row[4]<=len(data) and row[5]>=row[4], 'Invalid ELF load segment')
            segments.append(row)
    require(segments, 'No ELF load segments')
    return segments


def verify_boot(boot, fsbl, bit, application):
    require(len(boot)>=0xa0, 'Truncated Zynq boot header')
    raw=bit_payload(bit)
    swapped=b''.join(raw[i:i+4][::-1] for i in range(0,len(raw),4))
    bit_pos=boot.find(raw);order='native'
    if bit_pos<0:
        bit_pos=boot.find(swapped);order='swapped32'
    require(bit_pos>=0, 'Complete bit payload missing from BOOT')
    iht,pht=struct.unpack_from('<II',boot,0x98)
    require(iht+16<=len(boot), 'Image header table out of range')
    count=struct.unpack_from('<I',boot,iht+4)[0]
    app_segments=loads(application)
    require(count==2+len(app_segments) and pht+64*count<=len(boot), 'Unexpected BOOT partition count')
    image=struct.unpack_from('<I',boot,iht+12)[0]*4
    image_counts=[]
    for _ in range(3):
        require(image>0 and image+16<=len(boot), 'Image header out of range')
        nxt,first,_,number=struct.unpack_from('<4I',boot,image)
        require(first*4==pht+64*sum(image_counts), 'Image/partition header mismatch')
        image_counts.append(number);image=nxt*4
    require(image==0 and image_counts==[1,1,len(app_segments)], 'Expected FSBL / PL / application images')
    parts=[]
    for index in range(count):
        words=struct.unpack_from('<16I',boot,pht+64*index)
        require(sum(words)&0xffffffff==0xffffffff, 'Partition header checksum failed')
        start,length=words[5]*4,words[1]*4
        require(words[0]==words[1]==words[2] and start+length<=len(boot) and length>0, 'Invalid partition extent')
        parts.append(dict(index=index,offset=start,bytes=length,load=words[3],entry=words[4],attributes=words[6],sha256=hashlib.sha256(boot[start:start+length]).hexdigest()))
    require(parts[1]['offset']==bit_pos and parts[1]['attributes']&0x30==0x20, 'PL partition destination mismatch')
    padding=parts[1]['bytes']-len(raw)
    require(padding in (0,4,8,12), 'Unexpected PL payload padding')
    pad_word=bytes.fromhex('00000020' if order=='swapped32' else '20000000')
    require(boot[bit_pos+len(raw):bit_pos+len(raw)+padding]==pad_word*(padding//4), 'PL padding content mismatch')
    for data,selected,is_app in [(fsbl,parts[:1],False),(application,parts[2:],True)]:
        seen=[]
        for _,offset,virt,physical,length,memory,flags,align in loads(data):
            matches=[p for p in selected if p['load']<=physical and physical+length<=p['load']+p['bytes']]
            require(len(matches)==1, 'ELF load segment partition mismatch')
            part=matches[0];at=part['offset']+physical-part['load']
            require(boot[at:at+length]==data[offset:offset+length], 'BOOT differs from complete ELF load segment')
            if is_app:
                require(physical+memory<=0x08000000, 'Application overlaps reserved vision DDR region')
            seen.append(part['index'])
        require(set(seen)=={p['index'] for p in selected}, 'Unused or missing PS partition')
        require(all(p['attributes']&0x30==0x10 for p in selected), 'PS partition destination mismatch')
    return {'partitions':parts,'bit_payload_byte_order':order,'image_counts':image_counts}
