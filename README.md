# Home Assistant Bash listener

## What?

Bash script that listens to specified state changes from entities in your Home Assistant server. Uses curl as a lightweight way of getting initial states, and websockets to monitor push events. Allows you to execute any command line code when an entity state changes.

### Optional

I've chosen to use Better Touch Tool (BTT) for Mac OS to act as an ultimate controller for the state events, which is why you'll see BTT references. BTT supports 5 custom variables for its Conditional Activation Group feature, but there are many other ways to handle state.

## Why?

Home Assistant has a companion app for Mac OS, yes, but it's responsible for pushing events to your HA server, not the other way around. It's possible to push scripted events back to your Mac from HA via SSH, but sometimes you cannot rely on that. The Mac -> HA direction is more reliable for this.

## Requirements

- Mac (or Unix) OS
- Cloud-accessible Home Assistant instance (via Nabu Casa or DIY)
  - Websocket enabled setup (`websocket_api` is NOT required in config)
  - Long-lived token to use for authorization on client
  - REST_API enabled on HA
  - Custom template entity with attributes for each entity's state (for initial status)
- `brew install websocat`
- `brew install jq`

## ENVVARS

- BEARER="the long lived auth token generated in your User settings in HA"
- REST_API="full url to your server/api/states"
- WSS_API="full url to your server/api/websocket"