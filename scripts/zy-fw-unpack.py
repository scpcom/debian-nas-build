# extract_fw.py
# Extract FW from a file 
import sys
import struct

bin_filename = sys.argv[1]
if len(sys.argv) > 2:
  out_directory = sys.argv[2] + "/"
else:
  out_directory = "./"

if out_directory == "/":
  out_directory = "./"

with open(bin_filename, "rb") as binary_file:
    binary_file.seek(0, 2)  # Seek the end
    num_bytes = binary_file.tell()  # Get the file size
    
    binary_file.seek(0)
    sig_bytes = binary_file.read(10)
    if sig_bytes == b"\x00\x00\x00\x00\x00\x00\x53\x49\x47\x04":
        print("Found FW Signature")
    header_size = 48
    count = header_size
    last_w = 0
    last_b_u = 0

    while num_bytes > count:
        binary_file.seek(count)
        two_bytes = binary_file.read(2)
        w = struct.unpack("H", two_bytes)
        four_bytes = binary_file.read(4)
        u = struct.unpack("i", four_bytes)
        count += 6 + u[0]
        if (w[0] >= 0x1000 and u[0] == 4) or w[0] == 0xffff:
            if w[0] == 0xffff:
                b_u = u
            else:
                b_four_bytes = binary_file.read(4)
                b_u = struct.unpack("i", b_four_bytes)
            if last_b_u > 0:
                print("DATA_" + format(last_w, "04x") + " -> " + format(last_b_u + header_size, "08x") + " " + str(b_u[0] - last_b_u + 1));
                binary_file.seek(last_b_u + header_size)
                data_bytes = binary_file.read(b_u[0] - last_b_u + 1)
                out_file = open(out_directory + "DATA_" + format(last_w, "04x"), 'wb')  # Output file
                out_file.write(data_bytes)
                out_file.close()
            #print(" -> " + format(b_u[0] + header_size, "08x"));
            last_w = w[0]
            last_b_u = b_u[0]
        else:
            print("DATA_" + format(w[0], "04x") + " " + str(u[0]));
            data_bytes = binary_file.read(u[0])
            out_file = open(out_directory + "DATA_" + format(w[0], "04x"), 'wb')  # Output file
            out_file.write(data_bytes)
            out_file.close()
   
    binary_file.close()

