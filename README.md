# battery-guard

Lightweight battery lifecycle manager for Termux.

## Features
- Notify at configurable thresholds (default: 20% low, 80% high)
- CSV logging of battery health
- Server mode: run command when battery is low
- Auto-start on boot via Termux:Boot

## Requirements
- Termux (F-Droid)
- Termux:API app
- `pkg install jq termux-api`

## Install
    git clone https://github.com/paxxpi0oow/battery-guard.git
    cd battery-guard
    bash install.sh

## Usage
    battery-guard status
    battery-guard start
    battery-guard stop
    battery-guard log 50

## License
MIT
