#!/bin/bash

# Homebrew's bin is not on the PATH that launchd (or BTT, or cron) hands a job:
# they use /bin:/usr/bin:/usr/local/bin:/usr/sbin:/sbin. websocat lives only in
# /opt/homebrew/bin, so without this the script dies with
# "websocat: command not found" while launchctl still reports state = running.
# Prepending also keeps launchd runs on the same jq as an interactive run --
# macOS ships its own /usr/bin/jq, which would otherwise silently take over.
[ -d /opt/homebrew/bin ] && PATH="/opt/homebrew/bin:$PATH"
export PATH

# Load credentials from the shared shell environment file, if present.
# Sourcing explicitly (rather than relying on inherited exports) means this
# works when launched by launchd/cron or a bash login shell, neither of which
# reads ~/.zshenv. The file is POSIX syntax, so bash and sh both handle it.
[ -r "$HOME/.config/shell/env" ] && . "$HOME/.config/shell/env"

# Fail loudly rather than sending an empty token and getting a confusing
# auth rejection from Home Assistant.
: "${BEARER:?not set - export it, or define it in ~/.config/shell/env}"
: "${WSS_API:?not set - export it, or define it in ~/.config/shell/env}"

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
    # Verbose per-message output, gated behind DEBUG. Useful when adding or
    # renaming attributes on the template sensor and you need to see exactly
    # what HA is pushing. Off by default: under launchd this goes to a log file
    # and would otherwise grow without bound.
    #   DEBUG=1 ./ws
    if [ -n "$DEBUG" ]; then
      echo "$line" | jq -r
    fi

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

# -n keeps the connection open for push event data.
#
# --ping-interval / --ping-timeout exist to catch the failure mode that is
# otherwise invisible: a wifi change, sleep/wake, or NAT timeout kills the TCP
# connection without a FIN, so websocat blocks forever on a dead socket. The
# process stays alive and simply stops receiving events. Pinging forces the
# connection to prove itself, and websocat exits when no Pong arrives — which
# turns a silent stall into a normal process exit that a supervisor (or the BTT
# activation-group alert) can actually see.
#
# Note the auth + subscribe payload arrives on stdin and is consumed once, so
# websocat's `autoreconnect:` overlay is NOT a substitute: a re-established
# socket would never re-authenticate. The process is the unit of recovery, not
# the socket — a fresh run re-auths, re-subscribes, and rebuilds the BTT
# variable from the template sensor's initial response.
echo "$ASK" | websocat -n --ping-interval 30 --ping-timeout 90 "$WSS_API" | websocketResponse
