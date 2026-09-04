# Home Assistant Bash listener

## What?

Bash script that listens to specified state changes from entities in your Home Assistant server. Uses wget (curl is broken in Mac OS 13.3) as a lightweight way of getting initial states, and websockets to monitor push events. Allows you to execute any command line code when an entity state changes.

### Optional

I've chosen to use Better Touch Tool (BTT) for Mac OS to act as an ultimate controller for the state events, which is why you'll see BTT references. BTT supports 5 custom variables for its Conditional Activation Group feature, but there are many other ways to handle state.

## Why?

Home Assistant has a companion app for Mac OS, yes, but it's responsible for pushing events to your HA server, not the other way around. It's possible to push scripted events back to your Mac from HA via SSH, but sometimes you cannot rely on that. The Mac -> HA direction is more reliable for this.

## Requirements

- Mac (or Unix) OS
- Cloud-accessible Home Assistant instance (via Nabu Casa or DIY)
  - Websocket enabled setup (`websocket_api` is NOT required in config)
  - Long-lived token to use for authorization on client
  - Custom template entity with attributes for each entity's state (for initial status)*
- `brew install websocat`
- `brew install jq`
- `brew install wget`
- Optional: BetterTouchTool (currently the only controller/handler)

### Home Assistant Template Sensor Example:

```yaml
- platform: template
  sensors:
    btt_sensors:
      friendly_name: "BTT Sensors"
      value_template: |
        {{ expand("input_boolean.me_meeting","input_boolean.work_auto_lock","binary_sensor.work_headset","person.me","switch.work_vpn","binary_sensor.work_skype_state")
         | sort(attribute= 'last_changed', reverse=true)
         | map(attribute ='last_updated')
         | first | as_local
        }}
      attribute_templates:
        input_boolean.me_meeting: |
          {{ states("input_boolean.me_meeting") }}
        input_boolean.work_auto_lock: |
          {{ states("input_boolean.work_auto_lock") }}
        binary_sensor.work_headset: |
          {{ states("binary_sensor.work_headset") }}
        person.me: |
          {{ states("person.me") }}
        switch.work_vpn: |
          {{ states("switch.work_vpn") }}
        binary_sensor.work_skype_state: |
          {{ states("binary_sensor.work_skype_state") }}
```

## ENVVARS

- `BEARER` — the long-lived auth token generated in your User settings in HA
- `WSS_API` — full websocket URL, e.g. `wss://your-server/api/websocket`

Note the name is `WSS_API`, not `WS_API`. Earlier revisions of this README had the
latter, which does not match what `ws` reads and results in `websocat` being handed
an empty URL.

### Supplying them

`ws` sources `~/.config/shell/env` on startup if that file exists, so the variables can
live there instead of being exported by hand:

```sh
# ~/.config/shell/env   (chmod 600)
export HA_TOKEN='<long-lived token>'
export HA_BASE_URL='https://your-server'

export BEARER="$HA_TOKEN"
export WSS_API="wss://${HA_BASE_URL#https://}/api/websocket"
```

Keep that file to plain `export NAME=value` lines — it is also read by non-bash
consumers (`/bin/sh`), so shell-specific syntax will break them.

Exporting `BEARER` and `WSS_API` by any other means still works; the file is optional.
If neither is set, `ws` now exits immediately with a message instead of failing at the
auth step.

### DEBUG

`DEBUG=1 ./ws` prints every message HA pushes, via `jq`. Useful when adding or renaming
attributes on the template sensor and you need to see exactly what is arriving. Off by
default, since the output is unbounded and would fill a log file when run under a
supervisor.

### Running it unattended

`ws` exits on every failure it can detect — a clean close when HA restarts, and a
`--ping-timeout` drop when the socket dies without a FIN (wifi change, dock disconnect,
sleep/wake). That makes it safe to hand to a supervisor: restarting the process is full
recovery, because a fresh run re-authenticates, re-subscribes, and rebuilds the BTT
variable from the template sensor's initial response.

A macOS LaunchAgent with `RunAtLoad` + `KeepAlive` + `ThrottleInterval 30` is enough.
Two things to get right:

- **PATH.** launchd hands a job `/bin:/usr/bin:/usr/local/bin:/usr/sbin:/sbin`, which does
  not include Homebrew. `ws` prepends `/opt/homebrew/bin` itself, so no plist
  `EnvironmentVariables` are needed. Without it the script dies with
  `websocat: command not found` while `launchctl` still reports `state = running`.
- **Only one subscriber.** Running under launchd *and* in a terminal at the same time
  means two connections fighting over the same BTT variable.

Point `StandardOutPath` / `StandardErrorPath` at a log file — worth doing, since a
terminal tab launched with a trailing `;exit` closes the instant `ws` dies and takes the
error output with it.
