#!/bin/bash

# Home assistant entity IDs to monitor
ENTITY1="input_boolean.adamo_meeting"
ENTITY2="input_boolean.work_auto_lock"
ENTITY3="binary_sensor.work_headset"
ENTITY4="person.adamo"
ENTITY5="switch.work_vpn"
ENTITY6="binary_sensor.work_skype_state"

# Setup relative path for secondary scripts
parent_path=$(
  cd "$(dirname "${BASH_SOURCE[0]}")"
  pwd -P
)

# Run initial state helper
cd "$parent_path" && ./status

# Setup websocket API state subscribers
read -r -d '' ASK <<EOF
{"type": "auth", "access_token": "${BEARER}"}
{"id": 1, "type": "subscribe_trigger", "trigger": { "platform": "state", "entity_id": "${ENTITY1}" }}
{"id": 2, "type": "subscribe_trigger", "trigger": { "platform": "state", "entity_id": "${ENTITY2}" }}
{"id": 3, "type": "subscribe_trigger", "trigger": { "platform": "state", "entity_id": "${ENTITY3}" }}
{"id": 4, "type": "subscribe_trigger", "trigger": { "platform": "state", "entity_id": "${ENTITY4}" }}
{"id": 5, "type": "subscribe_trigger", "trigger": { "platform": "state", "entity_id": "${ENTITY5}" }}
{"id": 6, "type": "subscribe_trigger", "trigger": { "platform": "state", "entity_id": "${ENTITY6}" }}
EOF

# Websocket response handler
websocketResponse() {
  local line
  while IFS= read -r line; do
    json=$(echo "$line" | jq '.event?')
    if [[ $json != "null" ]]; then
      entity_id=$(echo "$json" | jq -r '.variables.trigger.to_state.entity_id')
      to_state=$(echo "$json" | jq -r '.variables.trigger.to_state.state')

      echo "$json" | jq '.variables.trigger.to_state'

      INDEX=1

      if [[ $entity_id == "${ENTITY2}" ]]; then
        INDEX=2
      elif [[ $entity_id == "${ENTITY3}" ]]; then
        INDEX=3
      elif [[ $entity_id == "${ENTITY4}" ]]; then
        INDEX=4
      elif [[ $entity_id == "${ENTITY5}" ]]; then
        INDEX=5
      elif [[ $entity_id == "${ENTITY6}" ]]; then
        INDEX=6
      fi

      # Perform actions with this new state:
      ./controllers/btt "$INDEX" "$to_state"
    fi
  done
}

while true; do
  echo "$ASK"
  sleep 1
done | websocat $WSS_API | websocketResponse
