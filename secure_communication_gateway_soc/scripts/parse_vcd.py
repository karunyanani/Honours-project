import re

import os

script_dir = os.path.dirname(os.path.abspath(__file__))
vcd_path = os.path.join(script_dir, "..", "build", "interconnect.vcd")
sigs = {}

with open(vcd_path) as f:
    for line in f:
        line = line.strip()
        if line.startswith('$var'):
            parts = line.split()
            if len(parts) >= 5:
                code = parts[3]
                name = parts[4]
                if any(k in name for k in ['s0_awvalid', 's0_awready', 's0_wvalid', 's0_wready', 's0_bvalid', 'm_awvalid', 'm_wvalid', 'm_bvalid', 'state_reg']):
                    sigs[code] = name

print("Tracked signals:", sigs)

cur_time = 0
with open(vcd_path) as f:
    for line in f:
        line = line.strip()
        if line.startswith('#'):
            cur_time = int(line[1:])
            if cur_time > 150000:
                break
        elif cur_time >= 60000:
            for code, name in sigs.items():
                if line.endswith(code):
                    val = line[:-len(code)].strip()
                    print(f"{cur_time:6d} ps : {name:20s} = {val}")
