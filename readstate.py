#!/usr/bin/env python3
# Screen Time state reader.
#
# Reads day-state files with a descriptor-bound, no-follow, non-blocking open so
# the trust decision (regular file, not a symlink, not a blocking FIFO) is made
# by the SAME open() syscall that yields the descriptor we read from. There is
# no second name resolution, so there is no TOCTOU window for an attacker to
# swap the entry for a symlink or FIFO between a check and the read.
#
# Usage:
#   readstate.py today <maxbytes> <file>
#   readstate.py week  <maxbytes> <dir>
#
# Paths are passed as argv (never interpolated into a shell), so a crafted
# HOME/XDG_STATE_HOME cannot alter the program. Each file is read to at most
# <maxbytes>; week mode emits one JSON line per existing day file.

import os
import sys
import datetime


def read_file(path, maxbytes):
    # O_NOFOLLOW: refuse to follow a symlink (open fails with OSError/ELOP).
    # O_NONBLOCK: opening a FIFO returns immediately instead of blocking until a
    # writer connects; reads then return EOF, so we never stall the shell.
    try:
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
    except OSError:
        return b""
    try:
        data = b""
        while len(data) < maxbytes:
            try:
                chunk = os.read(fd, maxbytes - len(data))
            except OSError:
                break
            if not chunk:
                break
            data += chunk
        return data
    finally:
        os.close(fd)


def main():
    if len(sys.argv) < 4:
        sys.exit(2)
    mode = sys.argv[1]
    maxbytes = int(sys.argv[2])
    target = sys.argv[3]

    if mode == "today":
        sys.stdout.buffer.write(read_file(target, maxbytes))
        return

    if mode == "week":
        today = datetime.date.today()
        chunks = []
        for i in range(6, -1, -1):
            d = (today - datetime.timedelta(days=i)).strftime("%Y-%m-%d")
            data = read_file(os.path.join(target, d + ".json"), maxbytes)
            if data:
                chunks.append(data)
        if chunks:
            sys.stdout.buffer.write(b"\n".join(chunks))
        return

    sys.exit(2)


if __name__ == "__main__":
    main()
