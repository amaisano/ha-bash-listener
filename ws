#!/bin/bash

# Master sensor with attributes (see README)
ENTITY0="sensor.btt_sensors"

# Home assistant entity IDs to monitor
ENTITY1="input_boolean.adamo_meeting"
ENTITY2="input_boolean.work_auto_lock"
ENTITY3="binary_sensor.work_headset"
ENTITY4="person.adamo"
ENTITY5="switch.work_vpn"
ENTITY6="binary_sensor.work_skype_state"

# Setup websocket API state subscription
read -r -d '' ASK <<EOF
{"type": "auth", "access_token": "${BEARER}"}
{"id": 1, "type": "subscribe_entities", "entity_ids": ["${ENTITY0}"]}
EOF

# Websocket response handler
websocketResponse() {
  local line
  while IFS= read -r line; do
    json=$(echo "$line" | jq '.event?')
    if [[ $json != "null" ]]; then

      INDEX=1
      # .c will be present for entity attribute updates only,
      # not for initial main sensor status report
      change=$(echo "$json" | jq -r '.c?')

      if [[ $change != "null" ]]; then
        entity_id=$(echo "$json" | jq -r '.c?[][].a?|keys[]')
        to_state=$(echo "$json" | jq -r '.c?[][].a?[]')

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

        echo "$INDEX = $entity_id : $to_state"

        # Perform actions with this new state:
        ./controllers/btt "$INDEX" "$to_state"
      else
        ENTITIES=$(echo "$json" | jq -r '.a?[].a?' | jq 'to_entries')

        # Set current states at startup using combo sensor attributes
        echo "$ENTITIES" | jq -c -r '.[]' | while read item; do
          entity=$(jq -r '.key' <<<"$item")
          state=$(jq -r '.value' <<<"$item")

          if [[ $INDEX < 7 ]]; then
            echo "$INDEX = $entity : $state"
            ./controllers/btt "$INDEX" "$state"
          fi

          ((INDEX++))
        done
      fi
    fi
  done
}

# Use -n option to keep connection open for push event data:
echo "$ASK" | websocat -n $WSS_API | websocketResponse
