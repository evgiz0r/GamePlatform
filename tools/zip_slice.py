#!/usr/bin/env python3
"""Pull a few members out of a huge remote zip without downloading all of it.

    zip_slice.py <url> <out_dir> <name_prefix> [<name_prefix> ...]

Reads the central directory from the tail of the archive with an HTTP range request,
then fetches only the matching members. Members land in out_dir with their directory
part stripped. Uses curl for the transfers so proxies and CA bundles behave exactly as
they do for every other download on the box.
"""
import struct, subprocess, sys, zlib, os

def fetch(url, start, end):
    return subprocess.run(
        ["curl", "-sSL", "-r", "%d-%d" % (start, end), url],
        check=True, capture_output=True).stdout

def size_of(url):
    out = subprocess.run(["curl", "-sSLI", url], check=True, capture_output=True).stdout
    sizes = [int(l.split(b":")[1]) for l in out.splitlines() if l.lower().startswith(b"content-length:")]
    return sizes[-1]

def main():
    url, out_dir, prefixes = sys.argv[1], sys.argv[2], sys.argv[3:]
    total = size_of(url)
    tail = fetch(url, max(0, total - 65536), total - 1)
    eocd = tail.rfind(b"PK\x05\x06")
    if eocd < 0:
        sys.exit("no end-of-central-directory record found")
    cd_size, cd_off = struct.unpack("<II", tail[eocd + 12:eocd + 20])
    cd = fetch(url, cd_off, cd_off + cd_size - 1)
    pos = 0
    found = 0
    while pos + 46 <= len(cd) and cd[pos:pos + 4] == b"PK\x01\x02":
        method, = struct.unpack("<H", cd[pos + 10:pos + 12])
        csize, usize = struct.unpack("<II", cd[pos + 20:pos + 28])
        nlen, xlen, clen = struct.unpack("<HHH", cd[pos + 28:pos + 34])
        lho, = struct.unpack("<I", cd[pos + 42:pos + 46])
        name = cd[pos + 46:pos + 46 + nlen].decode()
        pos += 46 + nlen + xlen + clen
        if not any(name.startswith(p) for p in prefixes) or name.endswith("/"):
            continue
        head = fetch(url, lho, lho + 29)
        n2, x2 = struct.unpack("<HH", head[26:30])
        data_start = lho + 30 + n2 + x2
        raw = fetch(url, data_start, data_start + csize - 1)
        data = zlib.decompress(raw, -15) if method == 8 else raw
        if len(data) != usize:
            sys.exit("size mismatch for %s" % name)
        dest = os.path.join(out_dir, os.path.basename(name))
        with open(dest, "wb") as f:
            f.write(data)
        print("  %s (%d bytes)" % (dest, len(data)), file=sys.stderr)
        found += 1
    if not found:
        sys.exit("nothing in the archive matched %s" % prefixes)

if __name__ == "__main__":
    main()
