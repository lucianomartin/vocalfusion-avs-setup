#!/usr/bin/env bash
# Copyright 2021 XMOS LIMITED. This software is subject to the terms of the
# XMOS Public Licence, Version 1
pushd "$( dirname "${BASH_SOURCE[0]}" )" > /dev/null
SETUP_DIR="$( pwd )"
RPI_SETUP_REPO=vocalfusion-rpi-setup
RPI_SETUP_DIR=$SETUP_DIR/$RPI_SETUP_REPO
RPI_SETUP_SCRIPT=$RPI_SETUP_DIR/setup.sh

RPI_SETUP_TAG="feature/3610_evk"
AVS_DEVICE_SDK_TAG="feature/gpio_int_n"
AVS_SCRIPT="setup.sh"

# Valid values for XMOS device
VALID_XMOS_DEVICES="xvf3100 xvf3500 xvf3510 xvf3600-slave xvf3600-master xvf3610"
XMOS_DEVICE=

# Default device serial number if nothing is specified
DEVICE_SERIAL_NUMBER="123456"
# Disable GPIO keyword detector by default
GPIO_KEY_WORD_DETECTOR_FLAG=""

usage() {
  local VALID_XMOS_DEVICES_DISPLAY_STRING=
  local NUMBER_OF_VALID_DEVICES=$(echo $VALID_XMOS_DEVICES | wc -w)
  local i=1
  local SEP=
  # Build a string of valid device options
  for d in $VALID_XMOS_DEVICES; do
    if [[ $i -eq $NUMBER_OF_VALID_DEVICES ]]; then
      SEP=" or "
    fi
    VALID_XMOS_DEVICES_DISPLAY_STRING=$VALID_XMOS_DEVICES_DISPLAY_STRING$SEP$d
    SEP=", "
    (( ++i ))
  done

  cat <<EOT
usage: auto_install.sh [OPTIONS] [DEVICE-TYPE]

A JSON config file, config.json, must be present in the current working
directory. The config.json can be downloaded from developer portal and must
contain the following:
   "clientId": "<Auth client ID>"
   "productId": "<your product name for device>"

Optional parameters:
  -s <serial-number>  If nothing is provided, the default device serial number
                      is 123456
  -g          	      Flag to enable keyword detector on GPIO interrupt
  -h                  Display this help and exit
  DEVICE-TYPE         XMOS device to setup: $VALID_XMOS_DEVICES_DISPLAY_STRING
EOT
}

CONFIG_JSON_FILE="config.json"
if [ ! -f "$CONFIG_JSON_FILE" ]; then
    echo "error: config JSON file not found."
    echo
    usage
    exit 1
fi

OPTIONS=s:gh
while getopts "$OPTIONS" opt ; do
    case $opt in
        s )
            DEVICE_SERIAL_NUMBER="$OPTARG"
            ;;
        g ) GPIO_KEY_WORD_DETECTOR_FLAG="-g"
            ;;
        h )
            usage
            exit 1
            ;;
    esac
done
shift $(( OPTIND - 1 ))

if [[ $# -ge 1 ]]; then
  XMOS_DEVICE=$1
else
  echo No device specified.
  PS3="Type the number corresponding to one of the above devices: "
  select XMOS_DEVICE in $VALID_XMOS_DEVICES; do
    if [[ -n "$XMOS_DEVICE" ]]; then
      break;
    fi
  done
fi

# validate XMOS_DEVICE value
validate_device() {
  local DEV=$1
  shift
  for d in $*; do
    if [[ "$DEV" = "$d" ]]; then
      return 0
    fi
  done
  return 1
}
if ! validate_device $XMOS_DEVICE $VALID_XMOS_DEVICES; then
  echo "error: $XMOS_DEVICE is not a valid device type."
  echo
  usage
  exit 1
fi

# Exit if chromium browser is open
if pgrep chromium > /dev/null ; then
  echo "Error: Chromium browser is open"
  echo "Please close the browser and restart the installation procedure"
  exit 2
fi

# Amazon have changed the SDK directory structure. Prior versions will need to delete the directory before updating.
SDK_DIR=$HOME/sdk-folder
if [ -d $SDK_DIR ]; then
  echo "Delete $SDK_DIR directory"
  rm -rf $SDK_DIR
fi

mkdir $SDK_DIR

if [ -d $RPI_SETUP_DIR ]; then
  echo "Delete $RPI_SETUP_DIR directory"	
  rm -rf $RPI_SETUP_DIR
fi

git clone -b $RPI_SETUP_TAG https://github.com/lucianomartin/$RPI_SETUP_REPO.git

# Execute (rather than source) the setup scripts
echo "Installing VocalFusion ${XMOS_DEVICE:3} Raspberry Pi Setup..."
if $RPI_SETUP_SCRIPT $XMOS_DEVICE; then

  # The line below is needed to avoid the error:
  # E: Repository 'http://raspbian.raspberrypi.org/raspbian buster InRelease' changed its 'Suite' value from 'testing' to 'stable'
  # N: This must be accepted explicitly before updates for this repository can be applied. See apt-secure(8) manpage for details.
  sudo apt update --allow-releaseinfo-change
  echo "Installing Amazon AVS SDK..."
  wget -O $AVS_SCRIPT https://raw.githubusercontent.com/lucianomartin/avs-device-sdk/$AVS_DEVICE_SDK_TAG/tools/Install/$AVS_SCRIPT
  wget -O pi.sh https://raw.githubusercontent.com/lucianomartin/avs-device-sdk/$AVS_DEVICE_SDK_TAG/tools/Install/pi.sh
  wget -O genConfig.sh https://raw.githubusercontent.com/lucianomartin/avs-device-sdk/$AVS_DEVICE_SDK_TAG/tools/Install/genConfig.sh
  chmod +x $AVS_SCRIPT
AVS_CMD="./${AVS_SCRIPT} ${CONFIG_JSON_FILE} ${AVS_DEVICE_SDK_TAG} -s ${DEVICE_SERIAL_NUMBER} -x ${XMOS_DEVICE} ${GPIO_KEY_WORD_DETECTOR_FLAG}"
echo "Running command ${AVS_CMD}"
  if $AVS_CMD; then
    echo "Type 'sudo reboot' below to reboot the Raspberry Pi and complete the AVS setup."
  fi
fi

popd > /dev/null
