#!/usr/bin/env python3
# gcc-wrapper.py (Python 3 version) - parses compiler warnings
import errno, re, os, sys, subprocess

ofile = None
warning_re = re.compile(r"""(.*/|)([^/]+\.[a-z]+:\d+):(\d+:)? warning:""")

def interpret_warning(line):
    line = line.rstrip("\n")
    m = warning_re.match(line)
    if m:
        print("warning:", m.group(2), file=sys.stderr)

def run_gcc():
    args = sys.argv[1:]
    global ofile
    try:
        i = args.index("-o")
        ofile = args[i + 1]
    except (ValueError, IndexError):
        pass
    try:
        proc = subprocess.Popen(args, stderr=subprocess.PIPE, universal_newlines=True)
        for line in proc.stderr:
            print(line, end="", file=sys.stderr)
            interpret_warning(line)
        result = proc.wait()
    except OSError as e:
        result = e.errno
        if result == errno.ENOENT:
            print(args[0] + ":", e.strerror, file=sys.stderr)
            print("Is your PATH set correctly?", file=sys.stderr)
        else:
            print(" ".join(args), str(e), file=sys.stderr)
    return result

if __name__ == "__main__":
    sys.exit(run_gcc())
