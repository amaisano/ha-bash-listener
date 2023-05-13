#!/bin/bash

source ~/.profile

# Home assistant entity IDs to monitor
ENTITY1="input_boolean.adamo_meeting"
ENTITY2="input_boolean.work_auto_lock"
ENTITY3="binary_sensor.work_headset"
ENTITY4="person.adamo"
ENTITY5="switch.work_vpn"

# Get current states at startup
SENSOR="sensor.btt_sensors"
ENTITIES=$(curl -s -H "Authorization: Bearer ${BEARER}" ${REST_API}/${SENSOR} | jq -r '.attributes' | jq 'to_entries')
var=1

# Set current states at startup using combo sensor attributes
echo "$ENTITIES" | jq -c -r '.[]' | while read item; do
  entity=$(jq -r '.key' <<<"$item")
  state=$(jq -r '.value' <<<"$item")

  if [[ $var < 6 ]]; then
    echo "$var = $entity : $state"
    osascript -e "tell application \"BetterTouchTool\" to set_string_variable \"customVariable${var}\" to \"${state}\"" >/dev/null
  fi

  ((var++))
done

read -r -d '' ASK <<EOF
{"type": "auth", "access_token": "${BEARER}"}
{"id": 1, "type": "subscribe_trigger", "trigger": { "platform": "state", "entity_id": "${ENTITY1}" }}
{"id": 2, "type": "subscribe_trigger", "trigger": { "platform": "state", "entity_id": "${ENTITY2}" }}
{"id": 3, "type": "subscribe_trigger", "trigger": { "platform": "state", "entity_id": "${ENTITY3}" }}
{"id": 4, "type": "subscribe_trigger", "trigger": { "platform": "state", "entity_id": "${ENTITY4}" }}
{"id": 5, "type": "subscribe_trigger", "trigger": { "platform": "state", "entity_id": "${ENTITY5}" }}
EOF

myfunc() {
  local line
  while IFS= read -r line; do
    json=$(echo "$line" | jq '.event?')
    if [[ $json != "null" ]]; then
      entity_id=$(echo "$json" | jq -r '.variables.trigger.to_state.entity_id')
      to_state=$(echo "$json" | jq -r '.variables.trigger.to_state.state')

      echo "$json" | jq '.variables.trigger.to_state'

      # BTT meeting context is on customVariable1
      customVariable=1

      # BTT lock context is on customVariable2
      if [[ $entity_id == "${ENTITY2}" ]]; then
        customVariable=2
      elif [[ $entity_id == "${ENTITY3}" ]]; then
        customVariable=3
      elif [[ $entity_id == "${ENTITY4}" ]]; then
        customVariable=4
      elif [[ $entity_id == "${ENTITY5}" ]]; then
        customVariable=5
      fi

      # curl -s "http://localhost:57109/set_string_variable/?variableName=customVariable${customVariable}&to=${to_state}" >/dev/null
      osascript -e "tell application \"BetterTouchTool\" to set_string_variable \"customVariable${customVariable}\" to \"${to_state}\"" >/dev/null
    fi
  done
}

while true; do
  echo "$ASK"
  sleep 1
done | websocat $WSS_API | myfunc
