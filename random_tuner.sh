#!/bin/bash

export SOURCE_ROOT=`pwd`
export NUM_INDIVIDUALS=20 # population size
export CPUs=$((`grep -c ^processor /proc/cpuinfo`-2))
# individuals must be even for crossover!
if [ $(echo "$((${NUM_INDIVIDUALS} % 2))" | bc -l) != 0 ]; then 
    echo "Number of individuals must be even!"
    exit
fi

############################## configuration settings ################################
export CROSS_RATE=0.8 # crossover probability
export MUT_RATE=0.1 # mutation probability
export SPLITSECONDS=0 # redundant parameter (set to 0)
export POOL=$(python -c "print ${NUM_INDIVIDUALS} / 5") # pool of individuals for tournament selection (25% population)
export LIMIT=36000 # time limit from BF sampling
export ITERATION=-1 # generation
export BEST_FITNESS=1000000 # initial best fitness function of the population
export THRESHOLD=15 # fitness function threshold
source ${SOURCE_ROOT}/defs.sh # configuration parameters
export SECONDS=0 # timer per generation
######################################################################################

if ls *.inc 1> /dev/null 2>&1; then rm -Rf *.inc; fi

############################## MASK NECESSARY CHANNELS HERE ##########################
# zapped_channels.inc
ZAP=0 # presence of channels to zap
declare -a ZAPPED_CHANNELS
ZAP1_MIN=800
ZAP1_MAX=850
ZAP2_MIN=860
ZAP2_MAX=900
ZAPPED_CHANNELS=(`seq ${ZAP1_MIN} ${ZAP1_MAX}` `seq ${ZAP2_MIN} ${ZAP2_MAX}`) 
if [ $ZAP = 1 ]; then
    for chan in ${ZAPPED_CHANNELS[@]}; do
        echo $chan >> zapped_channels.inc
    done
else
    touch zapped_channels.inc
fi
############################# FIXED CONFIGURATION FILES ##############################
# padding.inc
echo "# device padding" > padding.inc
echo ${DEVICE_NAME} ${DEVICE_PADDING} >> padding.inc

# integration_steps.inc
for step in ${DOWNSAMPLING[@]}; do
    echo $step >> integration_steps.inc
done
######################################################################################
# Randomisation
random()
{
    min=$1
    max=$2
    local rand=`echo "scale=1 ; $min + $((RANDOM % ($max-$min+1)))" | bc`
    echo $rand
}
export -f random

random_gaussian()
{
    min=$1
    max=$2
    local rand=`echo "scale=1 ; $min + $(( ($max-$min+1) * RANDOM / 32767 ))" | bc`
    echo $rand
}
export -f random_gaussian

# Set constant arrays
set_unroll_ds1()
{
    declare -a UNROLLS
    ind=0
    
    if [ $(( ${CHANNELS} / ${SUBBANDS} )) -lt 32 ]; then
        threshold=$(( ${CHANNELS} / ${SUBBANDS} ))
    else
        threshold=32
    fi

    for val in `seq 1 $threshold`; do
        if [ $(python -c "print $(( ${CHANNELS} / ${SUBBANDS} )) % $val") == 0 ]; then
            UNROLLS[$ind]=$val
            let ind+=1
        fi
    done
    echo ${UNROLLS[@]}
}
export -f set_unroll_ds1

set_unroll_ds2()
{
    declare -a UNROLLS
    ind=0
    if [ ${SUBBANDS} -lt 32 ]; then
        threshold=$SUBBANDS
    else
        threshold=32
    fi

    for val in `seq 1 $threshold`; do
        if [ $(python -c "print ${SUBBANDS} % $val") == 0 ]; then
            UNROLLS[$ind]=$val
            let ind+=1
        fi
    done
    echo ${UNROLLS[@]}
}
export -f set_unroll_ds2

set_nrsamplesperthread()
{
    declare -a NRSAMPLESPERTHREAD
    I=0
    for i in `seq 1 ${MAX_ITEMS_DIM0}`; do
        if [ $(python -c "print ${SAMPLES} % $i") == 0 ]; then
            NRSAMPLESPERTHREAD[$I]=$i
            let I+=1
        fi
    done
    echo ${NRSAMPLESPERTHREAD[@]}
}
export -f set_nrsamplesperthread

set_nrdmsperthread_ds1()
{
    declare -a NRDMSPERTHREAD
    J=0
    for j in `seq 1 ${MAX_ITEMS_DIM1}`; do
        if [ $(python -c "print ${SUBBANDING_DMS} % $j") == 0 ]; then
            NRDMSPERTHREAD[$J]=$j
            let J+=1  
        fi
    done
    echo ${NRDMSPERTHREAD[@]}
}
export -f set_nrdmsperthread_ds1

set_nrdmsperthread_ds2()
{
    declare -a NRDMSPERTHREAD
    J=0
    for j in `seq 1 ${MAX_ITEMS_DIM1}`; do
        if [ $(python -c "print ${DMS} % $j") == 0 ]; then
            NRDMSPERTHREAD[$J]=$j
            let J+=1
        fi
    done
    echo ${NRDMSPERTHREAD[@]}
}
export -f set_nrdmsperthread_ds2

set_nrsamplesperblock() # requires $nrSamplesPerThread
{
    nrSamplesPerThread=$1
    declare -a NRSAMPLESPERBLOCK
    I=0
    for i in `seq 1 ${MAX_DIM0}`; do
        if [ $(python -c "print $(( ${SAMPLES} / $nrSamplesPerThread )) % $i") == 0 ]; then
            NRSAMPLESPERBLOCK[$I]=$i
            let I+=1
        fi
    done
    echo ${NRSAMPLESPERBLOCK[@]}
}   
export -f set_nrsamplesperblock
    
set_nrdmsperblock_ds1() # requires $nrDMsPerThread
{
    nrDMsPerThread=$1
    declare -a NRDMSPERBLOCK
    J=0
    for j in `seq 1 ${MAX_DIM1}`; do
        if [ $(python -c "print $(( ${SUBBANDING_DMS} / $nrDMsPerThread )) % $j") == 0 ]; then
            NRDMSPERBLOCK[$J]=$j
            let J+=1
        fi
    done
    echo ${NRDMSPERBLOCK[@]}
}
export -f set_nrdmsperblock_ds1
    
set_nrdmsperblock_ds2() # requires $nrDMsPerThread
{
    nrDMsPerThread=$1
    declare -a NRDMSPERBLOCK
    J=0
    for j in `seq 1 ${MAX_DIM1}`; do
        if [ $(python -c "print $(( ${DMS} / $nrDMsPerThread )) % $j") == 0 ]; then
            NRDMSPERBLOCK[$J]=$j
            let J+=1
        fi
    done
    echo ${NRDMSPERBLOCK[@]}
}
export -f set_nrdmsperblock_ds2

set_nritemsd0() # requires $NRSAMPLES
{
    NRSAMPLES=$1
    declare -a NRITEMSD0
    ind=0

    if [ ${NRSAMPLES} -lt 255 ]; then
        threshold=${NRSAMPLES}
    else
        threshold=255
    fi

    for val in `seq 1 $threshold`; do
        if [ $(python -c "print ${NRSAMPLES} % $val") == 0 ]; then
            NRITEMSD0[$ind]=$val
            let ind+=1
        fi
    done
    echo ${NRITEMSD0[@]}
}
export -f set_nritemsd0

set_nrthreadsd0() # requires $NRSAMPLES and $nrItemsD0
{
    NRSAMPLES=$1
    nrItemsD0=$2
    declare -a NRTHREADSD0
    ind=0        

    if [ $(( ${NRSAMPLES} / $nrItemsD0 )) -lt 1024 ]; then
        threshold=$(( ${NRSAMPLES} / $nrItemsD0 ))
    else
        threshold=1024
    fi

    for val in `seq 1 $threshold`; do
        if [ $(python -c "print $((${NRSAMPLES} / $nrItemsD0)) % $val") == 0 ]; then
            NRTHREADSD0[$ind]=$val
            let ind+=1
        fi
    done 
    echo ${NRTHREADSD0[@]}
}
export -f set_nrthreadsd0

############################## initialise individuals ##############################
# Initialise solutions ($1 -- input directory)
Initialisation()
{ 
    echo "Initializing individual $1..."
    source ${SOURCE_ROOT}/defs.sh
    # first copy constant configurations
    # zapped_channels.inc
    cp ${SOURCE_ROOT}/zapped_channels.inc $1/zapped_channels.inc
    # padding.inc
    cp ${SOURCE_ROOT}/padding.inc $1/padding.inc
    # integration_steps.inc
    cp ${SOURCE_ROOT}/integration_steps.inc $1/integration_steps.inc
    
    # now generate variable configurations

    # dedispersion_stepone.inc
    echo "# device DMs splitSeconds localMem unroll nrSamplesPerBlock nrDMsPerBlock nrSamplesPerThread nrDMsPerThread" > $1/dedispersion_stepone.inc
    localMem=$(random 0 1)
    
    # UNROLLS 
    UNROLLS_STR=$(set_unroll_ds1)
    read -a UNROLLS <<< ${UNROLLS_STR}
    index=$(random 1 ${#UNROLLS[@]})
    unroll=${UNROLLS[$(($index-1))]}
    unset UNROLLS
 
    # NRSAMPLESPERTHREAD + NRDMSPERTHREAD 
    NRSAMPLESPERTHREAD_STR=$(set_nrsamplesperthread)
    NRDMSPERTHREAD_STR=$(set_nrdmsperthread_ds1)
    read -a NRSAMPLESPERTHREAD <<< ${NRSAMPLESPERTHREAD_STR}
    read -a NRDMSPERTHREAD <<< ${NRDMSPERTHREAD_STR}

    while true; do
        ii=$(random 1 ${#NRSAMPLESPERTHREAD[@]})
        nrSamplesPerThread=${NRSAMPLESPERTHREAD[$(($ii-1))]}
        jj=$(random 1 ${#NRDMSPERTHREAD[@]})
        nrDMsPerThread=${NRDMSPERTHREAD[$(($jj-1))]}
        if [ $(($nrSamplesPerThread * $nrDMsPerThread)) -lt 255 ]; then
            break
        fi
    done

    # NRSAMPLESPERBLOCK + NRDMSPERBLOCK
    NRSAMPLESPERBLOCK_STR=$(set_nrsamplesperblock $nrSamplesPerThread)
    read -a NRSAMPLESPERBLOCK <<< ${NRSAMPLESPERBLOCK_STR}
    NRDMSPERBLOCK_STR=$(set_nrdmsperblock_ds1 $nrDMsPerThread)
    read -a NRDMSPERBLOCK <<< ${NRDMSPERBLOCK_STR}
    
    while true; do
        ii=$(random 1 ${#NRSAMPLESPERBLOCK[@]})
        nrSamplesPerBlock=${NRSAMPLESPERBLOCK[$(($ii-1))]}
        jj=$(random 1 ${#NRDMSPERBLOCK[@]})
        nrDMsPerBlock=${NRDMSPERBLOCK[$(($jj-1))]}
        if [ $(($nrSamplesPerBlock * $nrDMsPerBlock)) -lt 1024 ]; then
            break
        fi
    done
    
    unset NRSAMPLESPERTHREAD NRDMSPERTHREAD NRSAMPLESPERBLOCK NRDMSPERBLOCK

    echo ${DEVICE_NAME} ${SUBBANDING_DMS} ${SPLITSECONDS} $localMem $unroll $nrSamplesPerBlock $nrDMsPerBlock 1 $nrSamplesPerThread $nrDMsPerThread 1 >> $1/dedispersion_stepone.inc

    # dedispersion_steptwo.inc
    echo "# device DMs splitSeconds localMem unroll nrSamplesPerBlock nrDMsPerBlock nrSamplesPerThread nrDMsPerThread" > $1/dedispersion_steptwo.inc
    localMem=$(random 0 1)

    # UNROLLS 
    UNROLLS_STR=$(set_unroll_ds2)
    read -a UNROLLS <<< ${UNROLLS_STR}
    index=$(random 1 ${#UNROLLS[@]})
    unroll=${UNROLLS[$(($index-1))]}
    unset UNROLLS

    # NRSAMPLESPERTHREAD + NRDMSPERTHREAD 
    NRSAMPLESPERTHREAD_STR=$(set_nrsamplesperthread)
    NRDMSPERTHREAD_STR=$(set_nrdmsperthread_ds2)
    read -a NRSAMPLESPERTHREAD <<< ${NRSAMPLESPERTHREAD_STR}
    read -a NRDMSPERTHREAD <<< ${NRDMSPERTHREAD_STR}
    
    while true; do
        ii=$(random 1 ${#NRSAMPLESPERTHREAD[@]})
        nrSamplesPerThread=${NRSAMPLESPERTHREAD[$(($ii-1))]}
        jj=$(random 1 ${#NRDMSPERTHREAD[@]})
        nrDMsPerThread=${NRDMSPERTHREAD[$(($jj-1))]}
        if [ $(($nrSamplesPerThread * $nrDMsPerThread)) -lt 255 ]; then
            break
        fi
    done

    # NRSAMPLESPERBLOCK + NRDMSPERBLOCK
    NRSAMPLESPERBLOCK_STR=$(set_nrsamplesperblock $nrSamplesPerThread)
    read -a NRSAMPLESPERBLOCK <<< ${NRSAMPLESPERBLOCK_STR}
    NRDMSPERBLOCK_STR=$(set_nrdmsperblock_ds2 $nrDMsPerThread)
    read -a NRDMSPERBLOCK <<< ${NRDMSPERBLOCK_STR}
    while true; do
        ii=$(random 1 ${#NRSAMPLESPERBLOCK[@]})
        nrSamplesPerBlock=${NRSAMPLESPERBLOCK[$(($ii-1))]}
        jj=$(random 1 ${#NRDMSPERBLOCK[@]})
        nrDMsPerBlock=${NRDMSPERBLOCK[$(($jj-1))]}
        if [ $(($nrSamplesPerBlock * $nrDMsPerBlock)) -lt 1024 ]; then
            break
        fi
    done
    
    unset NRSAMPLESPERTHREAD NRDMSPERTHREAD NRSAMPLESPERBLOCK NRDMSPERBLOCK

    echo ${DEVICE_NAME} ${DMS} ${SPLITSECONDS} $localMem $unroll $nrSamplesPerBlock $nrDMsPerBlock 1 $nrSamplesPerThread $nrDMsPerThread 1 >> $1/dedispersion_steptwo.inc

    # integration.inc
    echo "# device nrDMs integration nrThreadsD0 nrItemsD0" > $1/integration.inc   
    for step in ${DOWNSAMPLING[@]}; do
        NRSAMPLES=$(( ${SAMPLES} / $step ))
    
	# NRITEMSD0
	NRITEMSD0_STR=$(set_nritemsd0 ${NRSAMPLES})
	read -a NRITEMSD0 <<< ${NRITEMSD0_STR}
	index=$(random 1 ${#NRITEMSD0[@]})
	nrItemsD0=${NRITEMSD0[$(($index-1))]}
	unset NRITEMSD0

	# NRTHREADSD0
	NRTHREADSD0_STR=$(set_nrthreadsd0 ${NRSAMPLES} $nrItemsD0)
	read -a NRTHREADSD0 <<< ${NRTHREADSD0_STR}
	index=$(random 1 ${#NRTHREADSD0[@]})
	nrThreadsD0=${NRTHREADSD0[$(($index-1))]}
	unset NRTHREADSD0

        echo ${DEVICE_NAME} $(( ${SUBBANDING_DMS} * ${DMS} )) $step 1 $nrThreadsD0 1 1 $nrItemsD0 1 1 >> $1/integration.inc
    done

    # snr.inc
    echo "# device nrDMs nrSamples nrThreadsD0 nrItemsD0" > $1/snr.inc
    for step in `echo 1 ${DOWNSAMPLING[@]}`; do
        NRSAMPLES=$(( ${SAMPLES} / $step ))

        # NRITEMSD0
        NRITEMSD0_STR=$(set_nritemsd0 ${NRSAMPLES})
        read -a NRITEMSD0 <<< ${NRITEMSD0_STR}
        index=$(random 1 ${#NRITEMSD0[@]})
        nrItemsD0=${NRITEMSD0[$(($index-1))]} 
        unset NRITEMSD0

        # NRTHREADSD0
        NRTHREADSD0_STR=$(set_nrthreadsd0 ${NRSAMPLES} $nrItemsD0)
        read -a NRTHREADSD0 <<< ${NRTHREADSD0_STR}
        index=$(random 1 ${#NRTHREADSD0[@]})
        nrThreadsD0=${NRTHREADSD0[$(($index-1))]} 
        unset NRTHREADSD0

        echo ${DEVICE_NAME} $(( ${SUBBANDING_DMS} * ${DMS} )) ${NRSAMPLES} 1 $nrThreadsD0 1 1 $nrItemsD0 1 1 >> $1/snr.inc
    done
}
export -f Initialisation

# fitness function evaluation
Fitness() # ($1 - input directory for config files)
{
    conf=$1
    fitness=`bash performance_test.sh $conf 2> /dev/null`
    fit=`echo ${fitness##* }` # last word of the line, i.e. fitness score
    echo $fit
}
export -f Fitness

# Find best fitness value
Best()
{
    BEST=1000000
    for i in `seq 1 ${NUM_INDIVIDUALS}`
    do
        FITNESS=`cat ${SOURCE_ROOT}/confs$i/fitness.txt`
        if (( $(echo "${FITNESS} < ${BEST}" | bc -l ) )); then 
            BEST=${FITNESS}
        fi
    done
    echo $i ${BEST}
}

# Check individual
Check() # $1 -- individual
{
    for file in `ls $1/*.inc`
    do
        cat $file
    done
}

# Print out all current fitness values
Resume()
{
    for i in `seq 1 ${NUM_INDIVIDUALS}`
    do
        echo Individual $i:
        cat ${SOURCE_ROOT}/confs$i/fitness.txt
    done
}

# Print out all current fitness values
Resume()
{
    for i in `seq 1 ${NUM_INDIVIDUALS}`
    do
        echo Individual $i:
        cat ${SOURCE_ROOT}/confs$i/fitness.txt
    done
}

# Record population parameters per generation ('all' -- all configurations; 'best' -- only best configuration)
Record()
{
    if [ "$1" == "all" ]; then
    	INDIVIDUALS=($(seq 1 ${NUM_INDIVIDUALS}))
        COUNT=${NUM_INDIVIDUALS}
    elif [ "$1" == "best" ]; then
    	INDIVIDUALS=$(echo $(Best) | cut -d " " -f 1)
        COUNT=1
    fi

    # localmem, unroll, nrSamplesPerBlock, nrDMsPerBlock, nrSamplesPerThread, nrDMsPerThread  (line 1 - dedispersion_stepone)
    for i in ${INDIVIDUALS[@]}
    do
        echo -n `cat ${SOURCE_ROOT}/confs$i/dedispersion_stepone.inc | tail -1 | awk '{print $4}'` >> localmem.txt
        echo -n `cat ${SOURCE_ROOT}/confs$i/dedispersion_stepone.inc | tail -1 | awk '{print $5}'` >> unroll.txt
        echo -n `cat ${SOURCE_ROOT}/confs$i/dedispersion_stepone.inc | tail -1 | awk '{print $6}'` >> nrSamplesPerBlock.txt
        echo -n `cat ${SOURCE_ROOT}/confs$i/dedispersion_stepone.inc | tail -1 | awk '{print $7}'` >> nrDMsPerBlock.txt
        echo -n `cat ${SOURCE_ROOT}/confs$i/dedispersion_stepone.inc | tail -1 | awk '{print $9}'` >> nrSamplesPerThread.txt
        echo -n `cat ${SOURCE_ROOT}/confs$i/dedispersion_stepone.inc | tail -1 | awk '{print $10}'` >> nrDMsPerThread.txt
        if [ $i -lt ${COUNT} ]; then printf " " >> localmem.txt; printf " " >> unroll.txt; printf " " >> nrSamplesPerBlock.txt; printf " " >> nrDMsPerBlock.txt; printf " " >> nrSamplesPerThread.txt; printf " " >> nrDMsPerThread.txt
        else printf "\n" >> localmem.txt; printf "\n" >> unroll.txt; printf "\n" >> nrSamplesPerBlock.txt; printf "\n" >> nrDMsPerBlock.txt; printf "\n" >> nrSamplesPerThread.txt; printf "\n" >> nrDMsPerThread.txt
        fi
    done
    # localmem, unroll, nrSamplesPerBlock, nrDMsPerBlock, nrSamplesPerThread, nrDMsPerThread  (line 2 - dedispersion_steptwo)
    for i in ${INDIVIDUALS[@]}
    do
        echo -n `cat ${SOURCE_ROOT}/confs$i/dedispersion_steptwo.inc | tail -1 | awk '{print $4}'` >> localmem.txt
        echo -n `cat ${SOURCE_ROOT}/confs$i/dedispersion_steptwo.inc | tail -1 | awk '{print $5}'` >> unroll.txt
        echo -n `cat ${SOURCE_ROOT}/confs$i/dedispersion_steptwo.inc | tail -1 | awk '{print $6}'` >> nrSamplesPerBlock.txt
        echo -n `cat ${SOURCE_ROOT}/confs$i/dedispersion_steptwo.inc | tail -1 | awk '{print $7}'` >> nrDMsPerBlock.txt
        echo -n `cat ${SOURCE_ROOT}/confs$i/dedispersion_steptwo.inc | tail -1 | awk '{print $9}'` >> nrSamplesPerThread.txt
        echo -n `cat ${SOURCE_ROOT}/confs$i/dedispersion_steptwo.inc | tail -1 | awk '{print $10}'` >> nrDMsPerThread.txt
        if [ $i -lt ${COUNT} ]; then printf " " >> localmem.txt; printf " " >> unroll.txt; printf " " >> nrSamplesPerBlock.txt; printf " " >> nrDMsPerBlock.txt; printf " " >> nrSamplesPerThread.txt; printf " " >> nrDMsPerThread.txt
        else printf "\n" >> localmem.txt; printf "\n" >> unroll.txt; printf "\n" >> nrSamplesPerBlock.txt; printf "\n" >> nrDMsPerBlock.txt; printf "\n" >> nrSamplesPerThread.txt; printf "\n" >> nrDMsPerThread.txt   
        fi  
    done
    
    printf "\n" >> localmem.txt; printf "\n" >> unroll.txt; printf "\n" >> nrSamplesPerBlock.txt; printf "\n" >> nrDMsPerBlock.txt; printf "\n" >> nrSamplesPerThread.txt; printf "\n" >> nrDMsPerThread.txt
    
	# nrThreadsD0 nrItemsD0 (integration.inc; line i -- individual i)
	for j in `seq 2 10`; do 
		for i in ${INDIVIDUALS[@]}
		do
			line=`sed "${j}q;d" ${SOURCE_ROOT}/confs$i/integration.inc`
			echo -n `echo $line | awk '{print $5}'` >> nrThreadsD0.txt
			echo -n `echo $line | awk '{print $8}'` >> nrItemsD0.txt
			if [ $i -lt ${COUNT} ]; then
				printf " " >> nrThreadsD0.txt; printf " " >> nrItemsD0.txt
			else
				printf "\n" >> nrThreadsD0.txt; printf "\n" >> nrItemsD0.txt
			fi
		done
	done
	
	printf "\n" >> nrThreadsD0.txt; printf "\n" >> nrItemsD0.txt
	
	# nrThreadsD0 nrItemsD0 (snr.inc)
	for j in `seq 2 11`; do 
		for i in ${INDIVIDUALS[@]}
		do
			line=`sed "${j}q;d" ${SOURCE_ROOT}/confs$i/snr.inc`
			echo -n `echo $line | awk '{print $5}'` >> nrThreadsD0.txt
			echo -n `echo $line | awk '{print $8}'` >> nrItemsD0.txt
			if [ $i -lt ${COUNT} ]; then
				printf " " >> nrThreadsD0.txt; printf " " >> nrItemsD0.txt
			else
				printf "\n" >> nrThreadsD0.txt; printf "\n" >> nrItemsD0.txt
			fi
		done
	done
	
	printf "\n" >> nrThreadsD0.txt; printf "\n" >> nrItemsD0.txt
}

####################################################################################
###################################### Main() ######################################
####################################################################################

START=$(date +%s.%N) # start time
rm -Rf confs* offs* Iteration* fit.log execution.log *.txt

for i in `seq 1 ${NUM_INDIVIDUALS}`
do
    CONF=${SOURCE_ROOT}/confs$i
        if [ ! -e $CONF ]; then
            mkdir -p $CONF
        fi
done

# Begin random search process
until (( $(echo "${BEST_FITNESS} <= $THRESHOLD" | bc -l) || $(echo "$SECONDS > $LIMIT" | bc -l) ))
do
	let ITERATION+=1
	echo "Iteration $ITERATION"

	# Step 1: Initialisation
	for i in `seq 1 ${NUM_INDIVIDUALS}`; do
	    CONF=${SOURCE_ROOT}/confs$i
	    Initialisation $CONF
	done

	# Step 2: Fitness evaluation
	for i in `seq 1 ${NUM_INDIVIDUALS}`
	do
	    CONF=${SOURCE_ROOT}/confs$i
	    echo "Calculation of fitness $i..."
	    FITNESS=$(Fitness $CONF)
	    echo $FITNESS > $CONF/fitness.txt
	    cat $CONF/fitness.txt
	done

	# Update the best fitness function of the population
	BEST_FITNESS=$(echo $(Best) | cut -d " " -f 2)
	echo -e "$ITERATION \t ${BEST_FITNESS}" >> fit.log
	 
	# Resume fitness values
	echo "Fitness values for Iteration $ITERATION"
	Resume
	echo $SECONDS >> execution.log

	# Record all configurations at every generation
	Record all
	mkdir Iteration$ITERATION; mv *txt Iteration$ITERATION; cp -rn confs* Iteration$ITERATION
done

rm zapped_channels.inc padding.inc integration_steps.inc
END=$(date +%s.%N) # end time

DIFF=$(echo "$END - $START" | bc) # duration
echo "Total execution time: ${DIFF} sec" 
