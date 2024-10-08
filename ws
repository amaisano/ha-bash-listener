#!/bin/bash

# Init
INDEX=1 # Which BTT variable to store data on / HA WSS ID
ENTITY="sensor.btt_sensors" # Master template sensor (see README)

# Setup relative path for secondary scripts
parent_path=$(
  cd "$(dirname "${BASH_SOURCE[0]}")"
  pwd -P
)

# Put script into project context:
cd "$parent_path"

# Setup websocket API state subscription
read -r -d '' ASK <<EOF
{"type": "auth", "access_token": "${BEARER}"}
{"id": ${INDEX}, "type": "subscribe_entities", "entity_ids": ["${ENTITY}"]}
EOF

# Websocket response handler
websocketResponse() {
  local line
  while IFS= read -r line; do
    # Terminal output (verbose):
    echo "$line" | jq -r

    json=$(echo "$line" | jq '.event?')

    if [[ $json != "null" ]]; then
      # .c will be present for entity attribute updates only,
      # not for initial main sensor status report
      change=$(echo "$json" | jq -r '.c?')

      SAFE=''

      # On initial response:
      if [[ $change == "null" ]]; then
        RAW=$(echo "$json" | jq '.a?[].a?' | jq -rc 'del(.friendly_name)')

        # Escape quotes for use as string variable, and shorten keys by removing domain:
        SAFE=$(echo "$RAW" | sed -r "s/\"[^\"]*\.([^\"]*)\"/\"\1\"/g" | sed -e 's/\"/\\\"/g')

        # Set full JSON array string as BTT variable value (all entities and their current states):
        ./controllers/btt $INDEX $SAFE

      # On each change following initial response:
      else
        # Get previous variable value from BTT directly
        # @todo: store this locally or in a BTT getter controller instead of requiring BTT at this level
        CURRENT=$(osascript -e "tell application \"BetterTouchTool\" to return get_string_variable \"customVariable$INDEX\"")

        check=$(echo "$json" | jq -r '.c?[][].a?')

        if [[ $check != "null" ]]; then
          # Continue
          entity_id=$(echo "$json" | jq -r '.c?[][].a?|keys[]')
          to_state=$(echo "$json" | jq -r '.c?[][].a?[]')

          # Removes domain in entity_id to match originally set key values above:
          entity_id_safe=$(echo $entity_id | sed -r "s/^.*\.//g")
          new_state=$(echo "$CURRENT" | jq -rc ".$entity_id_safe = \"$to_state\"")

          # Escape quotes for use as string variable:
          SAFE=$(echo "$new_state" | sed -e 's/\"/\\\"/g')

          # Set full JSON array string as BTT variable value (all entities and their current states):
          ./controllers/btt $INDEX $SAFE
        fi
      fi
    fi
  done
}

# Use -n option to keep connection open for push event data:
echo "$ASK" | websocat -n $WSS_API | websocketResponse
