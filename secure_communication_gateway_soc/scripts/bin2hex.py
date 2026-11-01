#!/usr/bin/env python3
import sys

def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <input.bin> <output.hex>")
        sys.exit(1)
        
    bin_file = sys.argv[1]
    hex_file = sys.argv[2]
    
    with open(bin_file, "rb") as f:
        data = f.read()
        
    # Pad to 4-byte multiple
    if len(data) % 4 != 0:
        data += b'\x00' * (4 - (len(data) % 4))
        
    with open(hex_file, "w") as f:
        for i in range(0, len(data), 4):
            word = int.from_bytes(data[i:i+4], byteorder="little")
            f.write(f"{word:08x}\n")
            
    print(f"Successfully generated {hex_file} with {len(data)//4} 32-bit words ({len(data)} bytes).")

if __name__ == "__main__":
    main()

