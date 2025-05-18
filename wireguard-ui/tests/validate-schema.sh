#!/bin/bash

validate_schema_value() {
python3 -c '
import re,sys
config_regex="""\
^(?:|bool|email|url|port|device(?:\((?P<filter>subsystem=[a-z]+)\))?|str(?:\((?P<s_min>\d+)?,(?P<s_max>\d+)?\))?|password(?:\((?P<p_min>\d+)?,(?P<p_max>\d+)?\))?|int(?:\((?P<i_min>\d+)?,(?P<i_max>\d+)?\))?|float(?:\((?P<f_min>[\d\.]+)?,(?P<f_max>[\d\.]+)?\))?|match\((?P<match>.*)\)|list\((?P<list>.+)\))\??$\
"""
pattern=re.compile(config_regex)
sys.exit(0) if pattern.match(sys.stdin.read()) else sys.exit(1)
'
}
value_is_string() {
  [ "$(yq "${1}"' | type == "!!str"' config.yaml)" = true ]
}
value_is_sequence() {
  [ "$(yq "${1}"' | type == "!!seq"' config.yaml)" = true ]
}
get_value() {
  yq "${1}" config.yaml
}
get_seq_values() {
  yq "${1}"' | .[]' config.yaml
}
result=0
while read -r var; do
  schema_var='.schema."'"${var}"'"'
  if value_is_string "${schema_var}"; then
    if ! get_value "${schema_var}" | validate_schema_value; then
      echo "ERROR: ${schema_var} contains invalid value." >&2
      result=1
    fi
  elif value_is_sequence "${schema_var}"; then
    iteration=0
    while read -r item; do
      if ! validate_schema_value <<< "${item}"; then
        echo "ERROR: ${schema_var}[${iteration}] contains invalid value." >&2
        result=1
      fi
      iteration="$((iteration + 1))"
    done <<< "$(get_seq_values "${schema_var}")"
  else
    echo "ERROR: type not supported in ${schema_var}" >&2
    result=1
  fi
done <<< "$(yq '.schema | keys | .[]' config.yaml)"

exit "$result"
