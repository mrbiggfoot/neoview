#!/usr/bin/env python3
#
# Script to be executed from neovim terminal to open neoview window.
# Author:  Andrew Pyatkov <mrbiggfoot@gmail.com>
# License: MIT
#
"""
Open a preview window in the host neovim instance if required and call
<preview_fn> with <context_str> passed as an argument.
"""
import os
import sys

from neovim import attach

if len(sys.argv) != 3:
    sys.stderr.write("Usage: %s <preview_fn> \"<context_str>\"\n" %
                     sys.argv[0])
    sys.exit(1)

addr = os.environ.get("NVIM_LISTEN_ADDRESS", None)
if not addr:
    sys.stderr.write("$NVIM_LISTEN_ADDRESS is not set!\n")
    sys.exit(1)

nvim = attach("socket", path=addr)
nvim.command("call neoview#run(\"%s\", \"%s\")" %
             (sys.argv[1], sys.argv[2]))
