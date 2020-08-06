#!/usr/bin/env python3
#
# Display all tags in the specified file for neoview.
# Author:  Andrew Pyatkov <mrbiggfoot@gmail.com>
# License: MIT
#
"""
Display all tags in the specified file for neoview.
Output: {file_name}\t{tag_address}\t{displayable_tag_info}
"""
import argparse
#import os
#import re
import subprocess

# Parse command line args.
parser = argparse.ArgumentParser()
parser.add_argument("file", help="File name to display tags from")
args = parser.parse_args()

filename = args.file

# Colors for the output, see for more info:
# https://en.wikipedia.org/wiki/ANSI_escape_code#3/4_bit
COLOR_TAGTYPE = '\033[1;35m'
COLOR_TAGNAME = ''
COLOR_COMMENT = '\033[0;32m'
COLOR_BAR = '\033[0;37m'
COLOR_RESET = '\033[m'

# Contains lists of [file_name, tag_address, tag_name, comment].
# 'file_name' is relative to the current directory.
# 'tag_address' can be a number or a "/^line$/".
tags = []

# Max length of a tag name.
max_tag_len = 0

cmd = 'ctags -f - --excmd=number %s' % filename

result = subprocess.check_output(cmd, shell=True)
out = result.decode("utf-8", errors="ignore").rstrip().split("\n")


def displayable_info(tagname, comment):
    cs = comment.split("\t", 1)
    return ('{}{:<' + str(max_tag_len) + '}{} {}|{}{}{}|{} {}{}{}').\
        format(
            COLOR_TAGNAME, tagname, COLOR_RESET,
            COLOR_BAR, COLOR_TAGTYPE, cs[0], COLOR_BAR, COLOR_RESET,
            COLOR_COMMENT, cs[1] if len(cs) == 2 else "", COLOR_RESET)

for l in out:
    # t[0] - tag name, t[1] - file name, t[2] - tag address and comment
    t = l.split("\t", 2)
    max_tag_len = max(max_tag_len, len(t[0]))
    # info[0] - tag address, info[1] - comment
    info = t[2].split(';"')
    tags.append([t[1], info[0], t[0], info[1].strip()])

for t in tags:
    print('%s\t%s\t%s' %
          (t[0], t[1], displayable_info(t[2], t[3])))
