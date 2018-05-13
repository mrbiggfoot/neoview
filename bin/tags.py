#!/usr/bin/env python3
#
# Tags searcher for neoview.
# Author:  Andrew Pyatkov <mrbiggfoot@gmail.com>
# License: MIT
#
"""
Find exactly matching tags in the specified tags file.
Output: {file_name}\0{tag_address}\0{displayable_tag_info}
Note: tags should be generated with "--tag-relative=yes".
"""
import os
import subprocess
import sys

if len(sys.argv) != 3:
    sys.stderr.write('Usage: %s <tagname> <tagfile>\n' % sys.argv[0])
    sys.exit(1)

# Colors for the output, see for more info:
# https://en.wikipedia.org/wiki/ANSI_escape_code#3/4_bit
COLOR_TAGTYPE   = '\033[1;35m'
COLOR_PATH      = '\033[1;34m'
COLOR_LINE      = ''
COLOR_COMMENT   = '\033[0;32m'
COLOR_RESET     = '\033[0m'

MAX_DISPLAY_PATH_LEN = 80

tagname = sys.argv[1]
tagfile = sys.argv[2]
tagfiledir = os.path.dirname(os.path.abspath(tagfile))

# Contains lists of [file_name, tag_address, comment].
# 'file_name' is relative to the current directory.
# 'tag_address' can be a number or a "/^line$/".
tags = []

# Maps file name to the dict of { line_number : line_str } to reolve.
# Initially line_str is None, meaning that the line needs resolution.
resolve_lines = {}

# Max length of a relative path to display.
max_rpath_len = 0


# Return displayable info string based on the passed info
def displayable_info(path, line, comment):
    if len(path) > max_rpath_len:
        path = '<' + path[-max_rpath_len + 1:]
    cs = comment.split("\t", 1)
    return ('{}[{}]{} {}{:<' + str(max_rpath_len) + '}{}: {}{}{}\t{}{}{}').\
        format(
            COLOR_TAGTYPE, cs[0], COLOR_RESET,
            COLOR_PATH, path, COLOR_RESET,
            COLOR_LINE, line, COLOR_RESET,
            COLOR_COMMENT, cs[1] if len(cs) is 2 else "", COLOR_RESET)

#
# Create 'tags' and 'resolve_lines'
#
out = subprocess.getoutput('look "%s" %s | grep -w "^%s"' %
                           (tagname, tagfile, tagname)).split("\n")
for l in out:
    # t[0] - tag name, t[1] - file name, t[2] - tag address and comment
    t = l.split("\t", 2)
    # info[0] - tag address, info[1] - comment
    info = t[2].split(';"')
    rpath = os.path.relpath("%s/%s" % (tagfiledir, t[1]))
    rpath_len = min(len(rpath), MAX_DISPLAY_PATH_LEN)
    if (rpath_len > max_rpath_len):
        max_rpath_len = rpath_len

    if info[0].isdigit():
        tags.append([rpath, int(info[0]), info[1].strip()])
        if rpath in resolve_lines:
            resolve_lines[rpath][int(info[0])] = None
        else:
            resolve_lines[rpath] = {int(info[0]): None}
    else:
        tags.append([rpath, info[0], info[1].strip()])

#
# Resolve the lines that are addressed by number
#
for rpath, rlines in resolve_lines.items():
    sorted_nums = sorted(rlines.keys())
    with open(rpath, 'r') as f:
        cur_line_num = 0
        sorted_nums_idx = 0
        while sorted_nums_idx < len(sorted_nums):
            # Look for line number 'num'
            num = sorted_nums[sorted_nums_idx]
            sorted_nums_idx = sorted_nums_idx + 1
            for line in f:
                cur_line_num = cur_line_num + 1
                if cur_line_num == num:
                    rlines[num] = line.rstrip()
                    break

#
# Print the tags using resolve_lines if needed
#
for t in tags:
    if type(t[1]) is int:
        line = displayable_info(t[0], resolve_lines[t[0]][t[1]], t[2])
    else:
        line = displayable_info(t[0], t[1][2:-2], t[2])
    print('%s\0%s\0%s' % (t[0], t[1], line))
