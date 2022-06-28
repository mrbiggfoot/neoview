#!/usr/bin/env python3
#
# Parallel gtags searcher for neoview.
# Author:  Andrew Pyatkov <mrbiggfoot@gmail.com>
# License: MIT
#
"""
Find exactly matching tags in the specified gtags database(s).
Output: {file_name}\t{tag_address}\t{displayable_tag_info}
"""
import argparse
import os
import subprocess

# Parse command line args.
parser = argparse.ArgumentParser(description='Search in gtags database(s)',
    formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument('-n', type=int, default=0,
      help='Number of parallel instances. Zero means use regular global '
      'instead of pglobal')
parser.add_argument("dbpath", help="Gtags DB path")
parser.add_argument("global_args", nargs=argparse.REMAINDER,
    help='Arguments to be passed to "global"')
args = parser.parse_args()

dbpath = os.path.abspath(args.dbpath)
num_inst = args.n

# Colors for the output, see for more info:
# https://en.wikipedia.org/wiki/ANSI_escape_code#3/4_bit
COLOR_TAGTYPE = '\033[1;35m'
COLOR_PATH = '\033[1;34m'
COLOR_LESS = '\033[1;36m'
COLOR_INFO = ''
COLOR_LINENUM = '\033[0;32m'
COLOR_BAR = '\033[0;37m'
COLOR_RESET = '\033[m'

MAX_DISPLAY_PATH_LEN = 80

# Max "file:line" length encountered, capped at MAX_DISPLAY_PATH_LEN.
max_loc_len = 0

gtags_env = os.environ.copy()

if num_inst == 0:
  gtags_env['GTAGSROOT'] = os.getcwd()
  gtags_env['GTAGSDBPATH'] = dbpath
  cmd = ['global', '--result=grep'] + args.global_args
else:
  cmd = ['pglobal', '-n', str(num_inst), dbpath, '--result=grep'] + \
        args.global_args

out = subprocess.check_output(cmd, env=gtags_env)
lines = out.decode('utf-8', errors='ignore').rstrip().split('\n')

# Produce displayable info for the tag
def displayable_info(path, linenum, info):
  less = ''
  loc_len = len(path) + 1 + len(linenum)
  if loc_len > max_loc_len:
    less = '<'
    path = path[-max_loc_len + len(linenum) + 2:]
  return ('{}{}{}{}{}:{}{:<' + str(max_loc_len - len(path) - len(less)  - 1) +
          '}{} {}|{} {}{}{}').\
    format(
      COLOR_LESS, less, COLOR_PATH, path, COLOR_RESET,
      COLOR_LINENUM, linenum, COLOR_RESET,
      COLOR_BAR, COLOR_RESET,
      COLOR_INFO, info, COLOR_RESET)

# Contains lists of [file_name, line, info].
out = []

# Process output and calculate max_loc_len
for line in lines:
  t = line.split(':', maxsplit=2)
  # t[0] - file, t[1] - line, t[2] - info
  out.append([t[0], t[1], t[2]])

  loc_len = min(len(t[0]) + 1 + len(t[1]), MAX_DISPLAY_PATH_LEN)
  if loc_len > max_loc_len:
    max_loc_len = loc_len

# Print output
for l in out:
  print('%s\t%s\t%s' % (l[0], l[1], displayable_info(l[0], l[1], l[2])))
