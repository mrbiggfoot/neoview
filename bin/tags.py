#!/usr/bin/env python3
#
# Tags searcher for neoview.
# Author:  Andrew Pyatkov <mrbiggfoot@gmail.com>
# License: MIT
#
"""
Find exactly matching tags in the specified tags file.
Output: {file_name}\t{tag_address}\t{displayable_tag_info}
Note: tags should be generated with "--tag-relative=yes".
"""
import argparse
import os
import subprocess

# Parse command line args.
parser = argparse.ArgumentParser()
parser.add_argument("tagname", help="Name of the tag to search")
parser.add_argument("tagfile", help="Tags file name")
parser.add_argument("-i", "--ignore-case", help="Ignore case",
                    action="store_true")
args = parser.parse_args()

tagname = args.tagname
tagfile = args.tagfile
ignore_case = args.ignore_case
tagfiledir = os.path.dirname(os.path.abspath(tagfile))

# Colors for the output, see for more info:
# https://en.wikipedia.org/wiki/ANSI_escape_code#3/4_bit
COLOR_TAGTYPE = '\033[1;35m'
COLOR_PATH = '\033[1;34m'
COLOR_LINE = ''
COLOR_COMMENT = '\033[0;32m'
COLOR_RESET = '\033[0m'

MAX_DISPLAY_PATH_LEN = 80

# Contains lists of [file_name, tag_address, comment].
# 'file_name' is relative to the current directory.
# 'tag_address' can be a number or a "/^line$/".
tags = []

# Maps file name to the dict of { line_number : line_str } to reolve.
# Initially line_str is None, meaning that the line needs resolution.
resolve_lines = {}

# Max length of a relative path to display.
max_rpath_len = 0

# Max length of a code line to display.
max_code_len = 0


# Return displayable info string based on the passed info
def displayable_info(path, line, comment):
    if len(path) > max_rpath_len:
        path = '<' + path[-max_rpath_len + 1:]
    cs = comment.split("\t", 1)
    return ('{}{:<' + str(max_rpath_len) + '}{} │{}{}{}│ {}{:' +
            str(max_code_len) + '}{} │ {}{}{}').\
        format(
            COLOR_PATH, path, COLOR_RESET,
            COLOR_TAGTYPE, cs[0], COLOR_RESET,
            COLOR_LINE, line, COLOR_RESET,
            COLOR_COMMENT, cs[1] if len(cs) is 2 else "", COLOR_RESET)

# Find the lines we need to process
if ignore_case:
    cmd = '(look %s %s; look %s %s) | rg --color never -N -i -w "^%s"' % \
        (tagname[0].upper(), tagfile, tagname[0].lower(), tagfile, tagname)
else:
    cmd = 'look "%s" %s | rg --color never -N -w "^%s"' % \
        (tagname, tagfile, tagname)

result = subprocess.check_output(cmd, shell=True)
out = result.decode("utf-8", errors="ignore").rstrip().split("\n")

#
# Create 'tags' and 'resolve_lines'
#
for l in out:
    # t[0] - tag name, t[1] - file name, t[2] - tag address and comment
    t = l.split("\t", 2)
    # info[0] - tag address, info[1] - comment
    info = t[2].split(';"')
    if t[1][0] is '/':
        rpath = os.path.relpath(t[1])
    else:
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
        max_code_len = max(len(info[0]) - 4, max_code_len)
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
                    max_code_len = max(len(line.rstrip()), max_code_len)
                    break

#
# Print the tags using resolve_lines if needed
#
for t in tags:
    if type(t[1]) is int:
        line = displayable_info(t[0], resolve_lines[t[0]][t[1]], t[2])
    else:
        line = displayable_info(t[0], t[1][2:-2], t[2])
    print('%s\t%s\t%s' % (t[0], t[1], line))
