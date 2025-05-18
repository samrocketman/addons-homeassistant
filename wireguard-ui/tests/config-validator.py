#!/usr/bin/env python3
import re
import sys
config_regex="""\
^(?:|bool|email|url|port|device(?:\((?P<filter>subsystem=[a-z]+)\))?|str(?:\((?P<s_min>\d+)?,(?P<s_max>\d+)?\))?|password(?:\((?P<p_min>\d+)?,(?P<p_max>\d+)?\))?|int(?:\((?P<i_min>\d+)?,(?P<i_max>\d+)?\))?|float(?:\((?P<f_min>[\d\.]+)?,(?P<f_max>[\d\.]+)?\))?|match\((?P<match>.*)\)|list\((?P<list>.+)\))\??$\
"""
pattern=re.compile(config_regex)
sys.exit(0) if pattern.match(sys.stdin.read()) else sys.exit(1)
