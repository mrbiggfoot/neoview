#!/usr/bin/env python3
#
# Script to be executed from neovim terminal to open neoview window.
# Author:  Andrew Pyatkov <mrbiggfoot@gmail.com>
# License: MIT
#
"""
Update neoview identified by <id> with the currently selected candidate
identified by <context_str>.
"""
import os
import sys

from neovim import attach

if len(sys.argv) != 3:
    sys.stderr.write(
        "Usage: %s <id> \"<context_str>\"\n" %
        sys.argv[0])
    sys.exit(1)

addr = os.environ.get("NVIM_LISTEN_ADDRESS", None)
if not addr:
    sys.stderr.write("$NVIM_LISTEN_ADDRESS is not set!\n")
    sys.exit(1)

nvim = attach("socket", path=addr)
ctx = sys.argv[2].replace("'", "''")
nvim.command("call neoview#update(%s, '%s')" % (sys.argv[1], ctx))
