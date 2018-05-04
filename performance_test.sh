#!/bin/bash
set +e
PIPELINE=$HOME/sc4/code/pipeline
RESULT=`pwd`
CONF=$1

source ${RESULT}/defs.sh

function Run
{
    echo $@
    TIMEOUT=3m
    timeout $TIMEOUT time $@
}

# Configuration files
PADDING="${CONF}/padding.inc"
ZAPPED_CHANNELS="${CONF}/zapped_channels.inc"
INTEGRATION_STEPS="${CONF}/integration_steps.inc"
DEDISPERSION_STEPONE="${CONF}/dedispersion_stepone.inc"
DEDISPERSION_STEPTWO="${CONF}/dedispersion_steptwo.inc"
INTEGRATION="${CONF}/integration.inc"
SNR="${CONF}/snr.inc"

# Fitness function
mkdir -p ${RESULT}/results
OUTFILE="`date +%d%m%Y_%H%M`"
Run taskset -c ${CPU} ${PIPELINE}/TransientSearch/bin/TransientSearch -opencl_platform ${OPENCL_PLATFORM} -opencl_device ${OPENCL_DEVICE} -device_name ${DEVICE_NAME} -padding_file ${PADDING} -zapped_channels ${ZAPPED_CHANNELS} -integration_steps ${INTEGRATION_STEPS} -integration_file ${INTEGRATION} -snr_file ${SNR} -subband_dedispersion -dedispersion_step_one_file ${DEDISPERSION_STEPONE} -dedispersion_step_two_file ${DEDISPERSION_STEPTWO} -input_bits ${INPUT_BITS} -output ${RESULT}/results/${OUTFILE} -subbands ${SUBBANDS} -subbanding_dms ${SUBBANDING_DMS} -subbanding_dm_first ${SUBBANDING_DM_FIRST} -subbanding_dm_step ${SUBBANDING_DM_STEP} -dms ${DMS} -dm_first ${DM_FIRST} -dm_step ${DM_STEP} -threshold 16 -random -width 50 -dm 100 -beams ${BEAMS} -synthesized_beams ${SYNTHESIZED_BEAMS} -batches ${BATCHES} -channels ${CHANNELS} -min_freq ${MIN_FREQ} -channel_bandwidth ${CHANNEL_BANDWIDTH} -samples ${SAMPLES} -sampling_time ${SAMPLING_TIME} -compact_results

if [ -e ${RESULT}/results/${OUTFILE}.stats ]; then
    SEARCH_TIME=`cat ${RESULT}/results/${OUTFILE}.stats | sed -n '4'p`
    SCORE=`echo "scale=3 ; ${SEARCH_TIME} / ${BEAM_FACTOR}" | bc -l`
    rm -rf ${RESULT}/results
else
    SCORE=1000000
fi

echo "Performance score: ${SCORE}"
