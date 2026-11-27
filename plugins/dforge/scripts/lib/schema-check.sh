# shellcheck shell=bash
# dr_schema_valid SCHEMA FILE - succeeds when FILE holds exactly one JSON value
# valid against SCHEMA, in the part of JSON Schema the review schemas use:
# type, required, properties, additionalProperties false, items and enum, at
# every depth. The schema goes to jq as an argument and the file on stdin, so
# no native program is handed a POSIX path.
dr_schema_valid() {
  local schema
  [ -f "$2" ] || return 1
  schema=$(jq -c . < "$1" 2>/dev/null) || return 1
  jq -e -s --argjson schema "$schema" '
    def valid($s):
      . as $v |
      (if $s.type == "object" then
         type == "object" and
         (($s.required - keys) | length == 0) and
         (if $s.additionalProperties == false then
            ((keys - ($s.properties | keys)) | length == 0)
          else true end) and
         all(to_entries[]; .key as $k | .value | valid($s.properties[$k]))
       elif $s.type == "array" then type == "array" and all(.[]; valid($s.items))
       elif $s.type == "integer" then type == "number" and floor == .
       else type == $s.type end) and
      (if $s | has("enum") then $s.enum | index($v) != null else true end);
    length == 1 and (.[0] | valid($schema))
  ' < "$2" >/dev/null 2>&1
}
