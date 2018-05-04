#!/bin/bash

# CPU core used to run the pipeline (important for affinity to OpenCL device)
CPU="3"

# OpenCL configuration
## Device settings
OPENCL_PLATFORM="0"
OPENCL_DEVICE="2"
## Name of OpenCL device (used for configuration files)
DEVICE_NAME="ARTS0"
## Size of the cache line of OpenCL device (in bytes)
DEVICE_PADDING="128"
## Number of OpenCL work-items running simultaneously
DEVICE_THREADS="32"

# Tuning
ITERATIONS="1"
## Constraints
MIN_THREADS="8"
MAX_THREADS="1024"
MAX_ITEMS="255"
## Dedispersion constraints
LOCAL="-local"
MAX_ITEMS_DIM0="64"
MAX_ITEMS_DIM1="32"
MAX_UNROLL="32"
MAX_DIM0="1024"
MAX_DIM1="128"

## Test parameters (do not modify)
INPUT_BITS="8"
SUBBANDS="32"
#SUBBANDING_DMS="4096"
SUBBANDING_DMS="2048"
SUBBANDING_DM_FIRST="0.0"
SUBBANDING_DM_STEP="2.4"
DMS="24"
DM_FIRST="0.0"
DM_STEP="0.1"
BEAMS="1"
SYNTHESIZED_BEAMS="1"
BATCHES="10"
CHANNELS="1536"
MIN_FREQ="1290.09765625"
CHANNEL_BANDWIDTH="0.1953125"
SAMPLES="25600"
SAMPLING_TIME="0.00004096"
DOWNSAMPLING=(10 25 50 100 200 400 800 1600 3200)
