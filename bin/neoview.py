#!/usr/bin/env python3
#
# Script to be executed from neovim terminal to open neoview window.
# Author:  Andrew Pyatkov <mrbiggfoot@gmail.com>
# License: MIT
#
"""
Open a preview window in the host neovim instance using <create_cmd> if
required, then call <preview_fn> with <context_str> passed as an argument.
"""
import os
import sys

from neovim import attach

if len(sys.argv) != 4:
    sys.stderr.write(
        "Usage: %s <create_cmd> <preview_fn> \"<context_str>\"\n" %
        sys.argv[0])
    sys.exit(1)

addr = os.environ.get("NVIM_LISTEN_ADDRESS", None)
if not addr:
    sys.stderr.write("$NVIM_LISTEN_ADDRESS is not set!\n")
    sys.exit(1)

nvim = attach("socket", path=addr)
nvim.command("call neoview#update(\"%s\", \"%s\", \"%s\")" %
             (sys.argv[1], sys.argv[2], sys.argv[3]))
