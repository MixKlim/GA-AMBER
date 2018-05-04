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
export ITERATION=0 # generation
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

# select individuals for crossover (tournament selection)
Selection()
{
declare -a INDIVIDUALS
for i in `seq 0 $((${NUM_INDIVIDUALS}-1))`
do
    INDEX=0
    # find the best fitness
    BEST=1000000
    for j in `seq 1 ${POOL}`
    do
        ind=$(( 1 + RANDOM % ${NUM_INDIVIDUALS} ))
        CONF=${SOURCE_ROOT}/confs${ind}
        FITNESS=$(cat "$CONF/fitness.txt")
        if (( $(echo "${FITNESS} < ${BEST}" | bc -l ) )); then
            BEST=${FITNESS}
            INDEX=${ind}
        fi
    done

    # no good individuals at all - pick random
    if [ $INDEX == 0 ]; then
        INDEX=$(( 1 + RANDOM % ${NUM_INDIVIDUALS} ))
    fi

    INDIVIDUALS[$i]=${INDEX}
done

# check if there are no or only few repeating pairs
flag=0
test=0

while [ $flag == 0 ]
do
    flag=1
    
    for i in `seq 0 2 $((${NUM_INDIVIDUALS}-1))`
    do
        if [[ ${INDIVIDUALS[$i]} -eq ${INDIVIDUALS[$((i+1))]} ]]; then
            flag=0
            let test+=1 
            break
        fi
    done

    if [ $flag == 0 ]; then
        for i in `seq 0 2 $((${NUM_INDIVIDUALS}-1))`
        do
            if [[ ${INDIVIDUALS[$i]} -eq ${INDIVIDUALS[$((i+1))]} ]]
            then
                ind=$(( 0 + RANDOM % ${NUM_INDIVIDUALS} ))
                temp=${INDIVIDUALS[$i]}
                INDIVIDUALS[$i]=${INDIVIDUALS[$ind]}
                INDIVIDUALS[$ind]=$temp
            fi
        done
    fi
    
    if [[ $test -gt $((${NUM_INDIVIDUALS} / 2)) ]]
    then
        index=0
        for i in ${INDIVIDUALS[@]}; do
            if [[ $i == $temp ]]; then let index+=1 ; fi
        done
        if [[ $index -gt $((${NUM_INDIVIDUALS} / 2)) ]]; then break; fi
    fi  
done

echo ${INDIVIDUALS[@]} # indices of selected candidates
}

swap_genes() # swap a pair of genes with a coin toss probability
{
    flag=0 # no swap
    gene1=`echo $1 | awk -v x=$3 '{print $x}'`
    gene2=`echo $2 | awk -v x=$3 '{print $x}'`
    X_GEN=`echo "scale=1 ; $((RANDOM % 10)) / 10" | bc -l`
    if (( $(echo "${X_GEN} <= 0.5" | bc -l ) )); then
        flag=1 # swap happened
        temp=$gene1
        gene1=$gene2
        gene2=$temp
    fi
    echo $gene1 $gene2 $flag
}
export -f swap_genes

# merging two individuals with a coin toss crossover ($1 - input config 1; $2 - input config 2)
Crossmix()
{
    X_CROSS=`echo "scale=1 ; $((RANDOM % 10)) / 10" | bc -l`
    if (( $(echo "${X_CROSS} <= ${CROSS_RATE}" | bc -l ) )); then # apply crossover
        if [[ ( "`echo $1 | xargs -n 1 basename`" == "zapped_channels.inc" ) || ( "`echo $1 | xargs -n 1 basename`" == "padding.inc" ) || ( "`echo $1 | xargs -n 1 basename`" == "integration_steps.inc" ) ]]; then
            continue # skip constant files
        else
            if [[ ( "`echo $1 | xargs -n 1 basename`" == "dedispersion_stepone.inc" ) || ( "`echo $1 | xargs -n 1 basename`" == "dedispersion_steptwo.inc" ) ]]; then
                begin1=`cut -d" " -f1-3 $1 | tail -1` # non-changing part from parent 1
                begin2=`cut -d" " -f1-3 $2 | tail -1` # non-changing part from parent 2
                line1=`tail -1 $1` # last line of parent 1
                line2=`tail -1 $2` # last line of parent 2
                # localMem
                merge=$(swap_genes "$line1" "$line2" 4) 
                localMem1=`echo $merge | awk '{print $1}'`
                localMem2=`echo $merge | awk '{print $2}'`
                # unroll
                merge=$(swap_genes "$line1" "$line2" 5)
                unroll1=`echo $merge | awk '{print $1}'`
                unroll2=`echo $merge | awk '{print $2}'`
                # nrSamplesPerThread
                merge=$(swap_genes "$line1" "$line2" 9)
                nrSamplesPerThread1=`echo $merge | awk '{print $1}'`
                nrSamplesPerThread2=`echo $merge | awk '{print $2}'`  
                flag1=`echo $merge | awk '{print $3}'`     
                # nrDMsPerThread
                merge=$(swap_genes "$line1" "$line2" 10)
                nrDMsPerThread1=`echo $merge | awk '{print $1}'`
                nrDMsPerThread2=`echo $merge | awk '{print $2}'`
                flag2=`echo $merge | awk '{print $3}'`  
                # reverse values if not satisfy conditions
                temp1=$nrSamplesPerThread1
                temp2=$nrDMsPerThread1
                if [[ $(($nrSamplesPerThread1 * $nrDMsPerThread1)) -ge 255 ]]; then                
                    if [ $flag1 == 1 ]; then
                        nrSamplesPerThread1=$nrSamplesPerThread2
                    fi
                    if [ $flag2 == 1 ]; then
                        nrDMsPerThread1=$nrDMsPerThread2
                    fi
                    
                fi
                if [[ $(($nrSamplesPerThread2 * $nrDMsPerThread2)) -ge 255 ]]; then 
                        if [ $flag1 == 1 ]; then
                        nrSamplesPerThread2=$temp1
                    fi
                    if [ $flag2 == 1 ]; then
                        nrDMsPerThread2=$temp2
                    fi
                fi
                # nrSamplesPerBlock
                merge=$(swap_genes "$line1" "$line2" 6)
                nrSamplesPerBlock1=`echo $merge | awk '{print $1}'`
                nrSamplesPerBlock2=`echo $merge | awk '{print $2}'`
                flag1=`echo $merge | awk '{print $3}'`     
                # nrDMsPerBlock
                merge=$(swap_genes "$line1" "$line2" 7)
                nrDMsPerBlock1=`echo $merge | awk '{print $1}'`
                nrDMsPerBlock2=`echo $merge | awk '{print $2}'`
                flag2=`echo $merge | awk '{print $3}'`  
        # reverse values if not satisfy conditions
        temp1=$nrSamplesPerBlock1
        temp2=$nrSamplesPerBlock1
        if [[ ( "`echo $1 | xargs -n 1 basename`" == "dedispersion_stepone.inc" ) ]]; then
            if [[ ($(python -c "print $(( ${SAMPLES} / $nrSamplesPerThread1 )) % $nrSamplesPerBlock1") != 0) || ($(python -c "print $(( ${SUBBANDING_DMS} / $nrDMsPerThread1 )) % $nrDMsPerBlock1") != 0) || ($(($nrSamplesPerBlock1 * $nrDMsPerBlock1)) -ge 1024) ]]; then
                if [ $flag1 == 1 ]; then
                    nrSamplesPerBlock1=$nrSamplesPerBlock2
                fi
                if [ $flag2 == 1 ]; then
                    nrSamplesPerBlock1=$nrSamplesPerBlock2
                fi  
            fi
            if [[ ($(python -c "print $(( ${SAMPLES} / $nrSamplesPerThread2 )) % $nrSamplesPerBlock2") != 0) || ($(python -c "print $(( ${SUBBANDING_DMS} / $nrDMsPerThread2 )) % $nrDMsPerBlock2") != 0) || ($(($nrSamplesPerBlock2 * $nrDMsPerBlock2)) -ge 1024)  ]]; then
                if [ $flag1 == 1 ]; then
                    nrSamplesPerBlock2=$temp1
                fi
                if [ $flag2 == 1 ]; then
                    nrSamplesPerBlock2=$temp2
                fi
            fi  
        elif [[ ( "`echo $1 | xargs -n 1 basename`" == "dedispersion_steptwo.inc" ) ]]; then
            if [[ ($(python -c "print $(( ${SAMPLES} / $nrSamplesPerThread1 )) % $nrSamplesPerBlock1") != 0) || ($(python -c "print $(( ${DMS} / $nrDMsPerThread1 )) % $nrDMsPerBlock1") != 0) || ($(($nrSamplesPerBlock1 * $nrDMsPerBlock1)) -ge 1024) ]]; then
                if [ $flag1 == 1 ]; then
                    nrSamplesPerBlock1=$nrSamplesPerBlock2
                fi
                if [ $flag2 == 1 ]; then
                    nrSamplesPerBlock1=$nrSamplesPerBlock2
                fi  
            fi
            if [[ ($(python -c "print $(( ${SAMPLES} / $nrSamplesPerThread2 )) % $nrSamplesPerBlock2") != 0) || ($(python -c "print $(( ${DMS} / $nrDMsPerThread2 )) % $nrDMsPerBlock2") != 0) || ($(($nrSamplesPerBlock2 * $nrDMsPerBlock2)) -ge 1024)  ]]; then
                if [ $flag1 == 1 ]; then
                    nrSamplesPerBlock2=$temp1
                fi
                if [ $flag2 == 1 ]; then
                    nrSamplesPerBlock2=$temp2
                fi
            fi  
        fi
                # offspring 1
                off1=`echo $begin1 $localMem1 $unroll1 $nrSamplesPerBlock1 $nrDMsPerBlock1 1 $nrSamplesPerThread1 $nrDMsPerThread1 1`
                sed -i '$ d' $1 # delete old line
                echo $off1 >> $1 # add new line     
                # offspring 2
                off2=`echo $begin2 $localMem2 $unroll2 $nrSamplesPerBlock2 $nrDMsPerBlock2 1 $nrSamplesPerThread2 $nrDMsPerThread2 1`
                sed -i '$ d' $2 # delete old line
                echo $off2 >> $2 # add new line
            elif [[ ("`echo $1 | xargs -n 1 basename`" == "integration.inc") || ("`echo $1 | xargs -n 1 basename`" == "snr.inc") ]]; then 
                if [[ "`echo $1 | xargs -n 1 basename`" == "integration.inc" ]]; then
                    lines=10
                else 
                    lines=11
                fi 
            
                for i in `seq 2 $lines`; do         
                    line1=`sed "${i}q;d" $1` # line of parent 1
                    line2=`sed "${i}q;d" $2` # line of parent 2
                    begin1=`echo $line1 | awk '{ print $1,$2,$3}'` # non-changing part from parent 1
                    begin2=`echo $line2 | awk '{ print $1,$2,$3}'` # non-changing part from parent 2
                    # nrItemsD0
                    merge=$(swap_genes "$line1" "$line2" 8)
                    nrItemsD01=`echo $merge | awk '{print $1}'`
                    nrItemsD02=`echo $merge | awk '{print $2}'`
                    flag1=`echo $merge | awk '{print $3}'`
                    # nrThreadsD0
                    merge=$(swap_genes "$line1" "$line2" 5)
                    nrThreadsD01=`echo $merge | awk '{print $1}'`
                    nrThreadsD02=`echo $merge | awk '{print $2}'`
                    flag2=`echo $merge | awk '{print $3}'`
            # reverse values if not satisfy conditions
            temp1=$nrItemsD01
            temp2=$nrThreadsD01
            if [[ "`echo $1 | xargs -n 1 basename`" == "integration.inc" ]]; then
                NRSAMPLES=$(( ${SAMPLES} / ${DOWNSAMPLING[$((i-2))]} ))
                if [[ ($(python -c "print $(( ${NRSAMPLES} / $nrItemsD01 )) % $nrThreadsD01") != 0) ]]; then
                    if [ $flag1 == 1 ]; then
                    nrItemsD01=$nrItemsD02
                fi
                if [ $flag2 == 1 ]; then
                    nrThreadsD01=$nrThreadsD02
                fi
                fi
                if [[ ($(python -c "print $(( ${NRSAMPLES} / $nrItemsD02 )) % $nrThreadsD02") != 0) ]]; then
                    if [ $flag1 == 1 ]; then
                    nrItemsD02=$temp1
                fi
                if [ $flag2 == 1 ]; then
                    nrThreadsD02=$temp2
                fi
                fi
            elif [[ "`echo $1 | xargs -n 1 basename`" == "snr.inc" ]]; then
                if [ $i == 2 ]; then
                    NRSAMPLES=${SAMPLES}
                else
                    NRSAMPLES=$(( ${SAMPLES} / ${DOWNSAMPLING[$((i-3))]} ))
                fi
                if [[ ($(python -c "print $(( ${NRSAMPLES} / $nrItemsD01 )) % $nrThreadsD01") != 0) ]]; then
                    if [ $flag1 == 1 ]; then
                    nrItemsD01=$nrItemsD02
                fi
                if [ $flag2 == 1 ]; then
                    nrThreadsD01=$nrThreadsD02
                fi
            fi
                if [[ ($(python -c "print $(( ${NRSAMPLES} / $nrItemsD02 )) % $nrThreadsD02") != 0) ]]; then
                    if [ $flag1 == 1 ]; then
                    nrItemsD02=$temp1
                fi
                if [ $flag2 == 1 ]; then
                    nrThreadsD02=$temp2
                fi
                fi  
            fi
                    # offspring 1
                    off1=`echo $begin1 1 $nrThreadsD01 1 1 $nrItemsD01 1 1`
                    sed -i "${i}s/.*/${off1}/" $1 # replace i-th line in parent 1
                    # offspring 2
                    off2=`echo $begin2 1 $nrThreadsD02 1 1 $nrItemsD02 1 1`
                    sed -i "${i}s/.*/${off1}/" $2 # replace i-th line in parent 2       
                done
            fi
        fi
    fi
}
export -f Crossmix

# merging two individuals with a one-point crossover ($1 - input config 1; $2 - input config 2)
Crossover()
{
    if [[ ("`echo $1 | xargs -n 1 basename`" == "zapped_channels.inc" ) || ( "`echo $1 | xargs -n 1 basename`" == "padding.inc" ) || ( "`echo $1 | xargs -n 1 basename`" == "integration_steps.inc" ) ]]; then
        continue # skip constant files
        else
            X_CROSS=`echo "scale=1 ; $((RANDOM % 10)) / 10" | bc -l`
            if (( $(echo "${X_CROSS} <= ${CROSS_RATE}" | bc -l ) )); then
                if [[ ( "`echo $1 | xargs -n 1 basename`" == "dedispersion_stepone.inc" ) || ( "`echo $1 | xargs -n 1 basename`" == "dedispersion_steptwo.inc" ) ]]; then    
                        COL=11 # number of columns in file (last line - parameters)
                        begin=4 # non-changing part + 1 (to avoid copy)
                    cross=`echo "$begin+$((RANDOM % $(($COL-$begin-2))))" | bc -l`
                    flag=0
                    if [[ $cross == 6 ]]; then # separation between nrSamplesPerBlock and nrDMsPerBlock
                        line1=`tail -1 $1` # get last line from parent 1
                        nrSamplesPerBlock1=`echo $line1 | awk -v x=$cross '{print $x}'`
                        nrDMsPerBlock1=`echo $line1 | awk -v x=$((cross+1)) '{print $x}'`
                        nrSamplesPerThread1=`echo $line1 | awk -v x=$((cross+3)) '{print $x}'`
                        nrDMsPerThread1=`echo $line1 | awk -v x=$((cross+4)) '{print $x}'`
                        line2=`tail -1 $2` # get last line from parent 2
                        nrSamplesPerBlock2=`echo $line2 | awk -v x=$cross '{print $x}'`
                        nrDMsPerBlock2=`echo $line2 | awk -v x=$((cross+1)) '{print $x}'`
                        nrSamplesPerThread2=`echo $line2 | awk -v x=$((cross+3)) '{print $x}'`
                        nrDMsPerThread2=`echo $line2 | awk -v x=$((cross+4)) '{print $x}'`

                        if [[ "`echo $1 | xargs -n 1 basename`" == "dedispersion_stepone.inc" ]]; then
                        if [[ ($(python -c "print $(( ${SAMPLES} / $nrSamplesPerThread2 )) % $nrSamplesPerBlock1") != 0) || ($(python -c "print $(( ${SAMPLES} / $nrSamplesPerThread1 )) % $nrSamplesPerBlock2") != 0) || ($(python -c "print $(( ${SUBBANDING_DMS} / $nrDMsPerThread1 )) % $nrDMsPerBlock2") != 0) || ($(python -c "print $(( ${SUBBANDING_DMS} / $nrDMsPerThread2 )) % $nrDMsPerBlock1") != 0) || ($(($nrSamplesPerBlock1 * $nrDMsPerBlock2)) -ge 1024) || ($(($nrSamplesPerBlock2 * $nrDMsPerBlock1)) -ge 1024) ]]; then # if any of such bad conditions, we have to change cross point
                                flag=1
                            while [[ $cross == 6 ]]; do
                                    cross=`echo "$begin+$((RANDOM % $(($COL-$begin-1))))" | bc -l`
                                done
                            fi
                        elif [[ "`echo $1 | xargs -n 1 basename`" == "dedispersion_steptwo.inc" ]]; then
                            if [[ ($(python -c "print $(( ${SAMPLES} / $nrSamplesPerThread2 )) % $nrSamplesPerBlock1") != 0) || ($(python -c "print $(( ${SAMPLES} / $nrSamplesPerThread1 )) % $nrSamplesPerBlock2") != 0) || ($(python -c "print $(( ${DMS} / $nrDMsPerThread1 )) % $nrDMsPerBlock2") != 0) || ($(python -c "print $(( ${DMS} / $nrDMsPerThread2 )) % $nrDMsPerBlock1") != 0) || ($(($nrSamplesPerBlock1 * $nrDMsPerBlock2)) -ge 1024) || ($(($nrSamplesPerBlock2 * $nrDMsPerBlock1)) -ge 1024) ]]; then # if any of such bad conditions, we have to change cross point
                                flag=1
                            while [[ $cross == 6 ]]; do
                                    cross=`echo "$begin+$((RANDOM % $(($COL-$begin-1))))" | bc -l`
                                done
                            fi
                        fi  
                    fi
                    if [[ $cross == 9 ]]; then # separation between nrSamplesPerThread and nrDMsPerThread
                    line1=`tail -1 $1` # get last line from parent 1
                        nrSamplesPerThread1=`echo $line1 | awk -v x=$cross '{print $x}'`
                        nrDMsPerThread1=`echo $line1 | awk -v x=$((cross+1)) '{print $x}'`
                        line2=`tail -1 $2` # get last line from parent 2
                        nrSamplesPerThread2=`echo $line2 | awk -v x=$cross '{print $x}'`
                        nrDMsPerThread2=`echo $line2 | awk -v x=$((cross+1)) '{print $x}'`
                                            
                        if [[ ($(($nrSamplesPerThread1 * $nrDMsPerThread2)) -ge 255) || ($(($nrSamplesPerThread2 * $nrDMsPerThread1)) -ge 255) ]]; then # bad condition, have to change
                            if [[ $flag == 0 ]]; then
                                while [[ $cross == 9 ]]; do
                                    cross=`echo "$begin+$((RANDOM % $(($COL-$begin-1))))" | bc -l`
                                done    
                            else
                                while [[ ($cross == 6) && ($cross == 9) ]]; do
                                    cross=`echo "$begin+$((RANDOM % $(($COL-$begin-1))))" | bc -l`
                                done    
                            fi
                        fi
                    fi
                    
                        # offspring 1
                        ind1=`cut -d" " -f1-$cross $1 | tail -1` # part from parent 1
                        ind2=`cut -d" " -f$(($cross+1))- $2 | tail -1` # part from parent 2
                        off1=`echo $ind1 $ind2`

                        # offspring 2
                        ind1=`cut -d" " -f1-$cross $2 | tail -1` # part from parent 2
                        ind2=`cut -d" " -f$(($cross+1))- $1 | tail -1` # part from parent 1
                        off2=`echo $ind1 $ind2`

                        sed -i '$ d' $1 # delete old line in parent 1
                        echo $off1 >> $1 # add new line in parent 1
                        sed -i '$ d' $2 # delete old line in parent 2
                        echo $off2 >> $2 # add new line in parent 2
                     elif [[ ("`echo $1 | xargs -n 1 basename`" == "integration.inc") || ("`echo $1 | xargs -n 1 basename`" == "snr.inc") ]]; then      
                        if [[ "`echo $1 | xargs -n 1 basename`" == "integration.inc" ]]; then
                            lines=10
                        else 
                                lines=11
                        fi
                        
                        COL=10 # number of columns in file
                        begin=5 # non-changing part + 1 (to avoid copy)
                        
                        for i in `seq 2 $lines`; do
                                line1=`sed "${i}q;d" $1` # line of parent 1
                                line2=`sed "${i}q;d" $2` # line of parent 2
                                nrThreadsD01=`echo $line1 | awk -v x=5 '{print $x}'`
                                nrItemsD01=`echo $line1 | awk -v x=8 '{print $x}'`
                                nrThreadsD02=`echo $line2 | awk -v x=5 '{print $x}'`
                                nrItemsD02=`echo $line2 | awk -v x=8 '{print $x}'`
                            cross=`echo "$begin+$((RANDOM % $(($COL-$begin-2))))" | bc -l`
                            # check the condition between nrThreadsD0 and nrItemsD0
                            if [[ "`echo $1 | xargs -n 1 basename`" == "integration.inc" ]]; then
                                NRSAMPLES=$(( ${SAMPLES} / ${DOWNSAMPLING[$((i-2))]} ))
                                if [[ ($(python -c "print $(( ${NRSAMPLES} / $nrItemsD01 )) % $nrThreadsD01") != 0) || ($(python -c "print $(( ${NRSAMPLES} / $nrItemsD02 )) % $nrThreadsD02") != 0) ]]; then continue; fi
                            elif [[ "`echo $1 | xargs -n 1 basename`" == "snr.inc" ]]; then
                             if [ $i == 2 ]; then
                                NRSAMPLES=${SAMPLES}
                             else
                                NRSAMPLES=$(( ${SAMPLES} / ${DOWNSAMPLING[$((i-3))]} ))
                             fi
                             if [[ ($(python -c "print $(( ${NRSAMPLES} / $nrItemsD01 )) % $nrThreadsD01") != 0) || ($(python -c "print $(( ${NRSAMPLES} / $nrItemsD02 )) % $nrThreadsD02") != 0) ]]; then continue; fi
                        fi
                            # offspring 1
                            ind1=`cut -d" " -f1-$cross $1 | sed "${i}q;d"` # part from parent 1
                            ind2=`cut -d" " -f$(($cross+1))- $2 | sed "${i}q;d"` # part from parent 2
                            off1=`echo $ind1 $ind2`
                            # offspring 2
                            ind1=`cut -d" " -f1-$cross $2 | sed "${i}q;d"` # part from parent 2
                            ind2=`cut -d" " -f$(($cross+1))- $1 | sed "${i}q;d"` # part from parent 1
                            off2=`echo $ind1 $ind2`

                            sed -i "${i}s/.*/${off1}/" $1 # replace i-th line in parent 1
                            sed -i "${i}s/.*/${off1}/" $2 # replace i-th line in parent 2   
                        done                    
                     fi
                fi
        fi
}
export -f Crossover

# randomly choose lines from file without repetitions ($1 -- number of lines; $2 -- possible range) [start from line 2!]
randgen()
{
    awk -v loop=$1 -v range=$2 'BEGIN{
      srand()
      do {
        numb = 2 + int(rand() * range)
        if (!(numb in prev)) {
           print numb
           prev[numb] = 1
           count++
        }
      } while (count<loop)
    }'
}
export -f randgen

# mutation ($1 -- input directory)
Mutate()
{
    echo "Mutation individual $1..."
    source ${SOURCE_ROOT}/defs.sh
    for file in `ls $1/*.inc | xargs -n 1 basename`
    do
        if [[ ( $file == "zapped_channels.inc" ) || ( $file == "padding.inc" ) || ( $file == "integration_steps.inc" ) ]]; then
            continue # skip constant files      
        else
            X_MUT=`echo "scale=1 ; $((RANDOM % 10)) / 10" | bc`
            if (( $(echo "${X_MUT} <= ${MUT_RATE}" | bc -l ) )); then
                line=`head -1 $1/$file` # get first line
                COL=`awk '{print NF}' $1/$file | sort -nu | head -n 1` # number of columns in file (first line - names)
                mut=$((RANDOM % $((${COL}-4))+5)) # gen to mutate -- skip '#' and first three constant genes
                genname=`echo $line | awk -v x=$mut '{print $x}'` # name of the gen to mutate  
                # localMem
                if [ $genname == "localMem" ]; then
                    ind=$(($mut-1))
                    indline=2
                    line=`tail -1 $1/$file` # get last line
                    oldgen=`echo $line | awk -v x=$ind '{print $x}'` # old value of the mutated gen
                    gen=$oldgen
                    until [ $gen != $oldgen ]; do
                        gen=$(random 0 1)
                    done
                # unroll
                elif [ $genname == "unroll" ]; then
                    ind=$(($mut-1))  
                    indline=2
                    line=`tail -1 $1/$file` # get last line
                    oldgen=`echo $line | awk -v x=$ind '{print $x}'` # old value of the mutated gen   
                    if [[ $file == "dedispersion_stepone.inc" ]]; then
                        UNROLLS_STR=$(set_unroll_ds1)
                    elif [[ $file == "dedispersion_steptwo.inc" ]]; then
                        UNROLLS_STR=$(set_unroll_ds2) 
                    fi         
                    read -a UNROLLS <<< ${UNROLLS_STR}
                    gen=$oldgen
                    until [ $gen != $oldgen ]; do
                        index=$(random 1 ${#UNROLLS[@]})
                        gen=${UNROLLS[$(($index-1))]}
                    done
                    unset UNROLLS
                # nrSamplesPerThread           
                elif [ $genname == "nrSamplesPerThread" ]; then
                    ind=$mut
                    indline=2
                    line=`tail -1 $1/$file` # get last line
                    nrDMsPerThread=`echo $line | awk -v x=$(($mut+1)) '{print $x}'` # dependence (nrDMsPerThread)
                    NRSAMPLESPERTHREAD_STR=$(set_nrsamplesperthread)
                    read -a NRSAMPLESPERTHREAD <<< ${NRSAMPLESPERTHREAD_STR}
                    index=$(random 1 ${#NRSAMPLESPERTHREAD[@]})
                    gen=${NRSAMPLESPERTHREAD[$(($index-1))]}
                    until [[ $(($gen * $nrDMsPerThread)) -lt 255 ]]; do
                        index=$(random 1 ${#NRSAMPLESPERTHREAD[@]})
                        gen=${NRSAMPLESPERTHREAD[$(($index-1))]}
                    done
                    unset NRSAMPLESPERTHREAD
                # nrDMsPerThread
                elif [ $genname == "nrDMsPerThread" ]; then
                    ind=$mut
                    indline=2
                    line=`tail -1 $1/$file` # get last line
                    nrSamplesPerThread=`echo $line | awk -v x=$(($mut-1)) '{print $x}'` # dependence (nrSamplesPerThread)
                    if [[ $file == "dedispersion_stepone.inc" ]]; then
                        NRDMSPERTHREAD_STR=$(set_nrdmsperthread_ds1)
                    elif [[ $file == "dedispersion_steptwo.inc" ]]; then
                        NRDMSPERTHREAD_STR=$(set_nrdmsperthread_ds2) 
                    fi
                    read -a NRDMSPERTHREAD <<< ${NRDMSPERTHREAD_STR}
                    index=$(random 1 ${#NRDMSPERTHREAD[@]})
                    gen=${NRDMSPERTHREAD[$(($index-1))]}
                    until [[ $(($nrSamplesPerThread * $gen)) -lt 255 ]]; do
                        index=$(random 1 ${#NRDMSPERTHREAD[@]})
                        gen=${NRDMSPERTHREAD[$(($index-1))]}
                    done
                    unset NRDMSPERTHREAD
                # nrSamplesPerBlock
                elif [ $genname == "nrSamplesPerBlock" ]; then
                    ind=$(($mut-1))
                    indline=2
                    line=`tail -1 $1/$file` # get last line
                    nrSamplesPerThread=`echo $line | awk -v x=$(($mut+2)) '{print $x}'` # dependence (nrSamplesPerThread)
                    nrDMsPerBlock=`echo $line | awk -v x=$mut '{print $x}'` # dependence (nrDMsPerBlock)
                    nrsamplesperblock_str=$(set_nrsamplesperblock $nrSamplesPerThread)
                    read -a nrsamplesperblock <<< ${nrsamplesperblock_str}
                    index=$(random 1 ${#nrsamplesperblock[@]})
                    gen=${nrsamplesperblock[$(($index-1))]}
                    until [[ $(($gen * $nrDMsPerBlock)) -lt 1024 ]]; do
                        index=$(random 1 ${#nrsamplesperblock[@]})
                        gen=${nrsamplesperblock[$(($index-1))]}
                    done
                    unset nrsamplesperblock
                # nrDMsPerBlock
                elif [ $genname == "nrDMsPerBlock" ]; then
                    ind=$(($mut-1))
                    indline=2
                    line=`tail -1 $1/$file` # get last line
                    nrDMsPerThread=`echo $line | awk -v x=$(($mut+2)) '{print $x}'` # dependence (nrDMsPerThread)
                    nrSamplesPerBlock=`echo $line | awk -v x=$(($mut-2)) '{print $x}'` # dependence (nrSamplesPerBlock)
                    if [[ $file == "dedispersion_stepone.inc" ]]; then
                        nrdmsperblock_str=$(set_nrdmsperblock_ds1 $nrDMsPerThread)
                    elif [[ $file == "dedispersion_steptwo.inc" ]]; then
                        nrdmsperblock_str=$(set_nrdmsperblock_ds2 $nrDMsPerThread)
                    fi
                    read -a nrdmsperblock <<< ${nrdmsperblock_str}
                    index=$(random 1 ${#nrdmsperblock[@]})
                    gen=${nrdmsperblock[$(($index-1))]}
                    until [[ $(($nrSamplesPerBlock * $gen)) -lt 1024 ]]; do
                            index=$(random 1 ${#nrdmsperblock[@]})
                            gen=${nrdmsperblock[$(($index-1))]}
                    done
                    unset nrdmsperblock
                # nrItemsD0  
                elif [ $genname == "nrItemsD0" ]; then
                    if [ $file == "integration.inc" ]; then
                        ind=$(($mut+2)) 
                        RANGE=${#DOWNSAMPLING[@]}
                        LOOP=$((1+RANDOM%$RANGE))
                        LINES=($(randgen $LOOP $RANGE))
                        for indline in ${LINES[@]}
                        do
                        line=`sed "${indline}q;d" $1/$file` # get line with the number 'indline'
                        integration=`echo $line | awk -v x=$(($mut-3)) '{print $x}'` # dependence (nrSamples)
                        nrsamples=$(( ${SAMPLES} / $integration ))
                        nritemsd0_str=$(set_nritemsd0 ${nrsamples})
                        read -a nritemsd0 <<< ${nritemsd0_str}
                        index=$(random 1 ${#nritemsd0[@]})
                        gen=${nritemsd0[$(($index-1))]}
                        unset nritemsd0
                        done
                    else
                        ind=$(($mut+2))
                        RANGE=$((${#DOWNSAMPLING[@]}+1))
                        LOOP=$((1+RANDOM%$RANGE))
                        LINES=($(randgen $LOOP $RANGE))
                        for indline in ${LINES[@]}
                        do
                        line=`sed "${indline}q;d" $1/$file` # get line with number 'indline'
                        nrsamples=`echo $line | awk -v x=$(($mut-3)) '{print $x}'` # dependence (nrSamples)
                        nritemsd0_str=$(set_nritemsd0 ${nrsamples})
                        read -a nritemsd0 <<< ${nritemsd0_str}
                        index=$(random 1 ${#nritemsd0[@]})
                        gen=${nritemsd0[$(($index-1))]}
                        unset nritemsd0
                        done
                    fi
                # nrThreadsD0
                elif [ $genname == "nrThreadsD0" ]; then
                    if [ $file == "integration.inc" ]; then
                        ind=$mut
                        RANGE=${#DOWNSAMPLING[@]}
                        LOOP=$((1+RANDOM%$RANGE))
                        LINES=($(randgen $LOOP $RANGE))
                        for indline in ${LINES[@]}
                        do
                        line=`sed "${indline}q;d" $1/$file` # get line with the number 'indline'
                        integration=`echo $line | awk -v x=$(($mut-2)) '{print $x}'` # dependence (nrSamples)
                        nrsamples=$(( ${SAMPLES} / $integration ))
                        nrItemsD0=`echo $line | awk -v x=$(($mut+3)) '{print $x}'` # dependence (nrItemsD0)
                        nrthreadsd0_str=$(set_nrthreadsd0 $nrsamples $nrItemsD0)
                        read -a nrthreadsd0 <<< ${nrthreadsd0_str}              
                        index=$(random 1 ${#nrthreadsd0[@]})
                        gen=${nrthreadsd0[$(($index-1))]}   
                        unset nrthreadsd0
                        done
                    else
                        ind=$mut
                        RANGE=$((${#DOWNSAMPLING[@]}+1))
                        LOOP=$((1+RANDOM%$RANGE))
                        LINES=($(randgen $LOOP $RANGE))
                        for indline in ${LINES[@]}
            do
                        line=`sed "${indline}q;d" $1/$file` # get line with number 'indline'
                        nrsamples=`echo $line | awk -v x=$(($mut-2)) '{print $x}'` # dependence (nrSamples)
                        nrItemsD0=`echo $line | awk -v x=$(($mut+3)) '{print $x}'` # dependence (nrItemsD0)  
                        nrthreadsd0_str=$(set_nrthreadsd0 $nrsamples $nrItemsD0)
                        read -a nrthreadsd0 <<< ${nrthreadsd0_str}
                        index=$(random 1 ${#nrthreadsd0[@]})
                        gen=${nrthreadsd0[$(($index-1))]} 
                        unset nrthreadsd0 
                        done                   
                    fi
                fi
                # replace this gen in a file
                mut=`echo $line | awk -v ind=$ind -v gen=$gen '{$ind = "'"$gen"'"; print}'` # replace gen at the right position
                sed -i "${indline}s/.*/${mut}/" $1/$file # replace the line
            fi  
        fi
    done
}
export -f Mutate

# replacement with ranking and no shuffling
Replace_norank()
{
    declare -a NEW_INDIVIDUALS
    SUM_FIT=0
    for i in `seq 1 ${NUM_INDIVIDUALS}`
    do
        OFF=${SOURCE_ROOT}/offs$i
        FITNESS=$(cat $OFF/fitness.txt)
        SUM_FIT=`echo "${SUM_FIT}+$FITNESS" | bc -l`
        if [ $i = 1 ]; then
            FIT_CHILD=$FITNESS # best offspring
        else
            if (( $(echo "$FITNESS < ${FIT_CHILD}" | bc -l) )); then
                FIT_CHILD=$FITNESS # update best offspring
            fi
        fi
    done

    # Mean fitness value
    MEAN_FIT=`python -c "print ${SUM_FIT} / ${NUM_INDIVIDUALS}"`
    IND=0
    
    # save better parents
    for i in `seq 1 ${NUM_INDIVIDUALS}`
    do
        CONF=${SOURCE_ROOT}/confs$i
        if [ -e $CONF ]; then
            FITNESS=$(cat $CONF/fitness.txt)
            if (( $(echo "$FITNESS < ${FIT_CHILD}" | bc -l) )); then
                NEW_INDIVIDUALS[$IND]=$CONF
                let IND+=1
            fi
        fi  
    done

    # add better children
    for i in `seq 1 ${NUM_INDIVIDUALS}`
    do

        OFF=${SOURCE_ROOT}/offs$i
        FITNESS=$(cat $OFF/fitness.txt)
        if (( $(echo "$IND <= $((${NUM_INDIVIDUALS}-1))" | bc -l) )); then
            if (( $(echo "$FITNESS <= ${MEAN_FIT}" | bc -l) )); then
                NEW_INDIVIDUALS[$IND]=$OFF
                let IND+=1
            fi
        else
            break
        fi
    done

    # add less good children (if still fit)
    for i in `seq 1 ${NUM_INDIVIDUALS}`
    do
        OFF=${SOURCE_ROOT}/offs$i
        FITNESS=$(cat $OFF/fitness.txt)
        if (( $(echo "$IND <= $((${NUM_INDIVIDUALS}-1))" | bc -l) )); then
            if (( $(echo "$FITNESS > ${MEAN_FIT}" | bc -l) )); then
                NEW_INDIVIDUALS[$IND]=$OFF
                let IND+=1
            fi
        else
            break
        fi
    done
    
    # make new individuals as parents and delete all others
    COUNT=1
    for path in ${NEW_INDIVIDUALS[@]}
    do
        TEMP=${SOURCE_ROOT}/TEMP$COUNT
        mkdir $TEMP
        cp $path/* $TEMP
        let COUNT+=1
    done
 
    for i in `seq 1 ${NUM_INDIVIDUALS}`
    do
        CONF=${SOURCE_ROOT}/confs$i
        if [ -e $CONF ]; then
            rm -Rf $CONF
        fi
        OFF=${SOURCE_ROOT}/offs$i
        rm -Rf $OFF
        mv ${SOURCE_ROOT}/TEMP$i $CONF
    done
}

Replace_sort() # replace by median with parent-child interchange
{
     declare -a OLD_FITNESS
     declare -a NEW_FITNESS
     
     # all fintess functions of parents
     ind=0
     for i in `seq 1 ${NUM_INDIVIDUALS}`
     do
         CONFS=${SOURCE_ROOT}/confs$i
         FITNESS=$(cat $CONFS/fitness.txt)
         OLD_FITNESS[$ind]=$FITNESS
         let ind+=1
     done
 
     # all fitness functions of offspring
     ind=0
     for i in `seq 1 ${NUM_INDIVIDUALS}`
     do
         OFFS=${SOURCE_ROOT}/offs$i
         FITNESS=$(cat $OFFS/fitness.txt)
         NEW_FITNESS[$ind]=$FITNESS
         let ind+=1
     done
 
     # sort arrays based on fitness functions (min-max)
     OLD_FITNESS_SORT=( $( printf "%s\n" "${OLD_FITNESS[@]}" | sort -n ) )
     NEW_FITNESS_SORT=( $( printf "%s\n" "${NEW_FITNESS[@]}" | sort -n ) )

     # pick halves from both best parents and offspring
     declare -a NEW_INDIVIDUALS
     
     oldset=($(seq 1 ${NUM_INDIVIDUALS}))
     newset=($(seq 1 ${NUM_INDIVIDUALS}))
     
     IND=0
     for i in `seq 1 $((${NUM_INDIVIDUALS} / 2))`
     do      
         for j in ${oldset[@]}
         do
             CONF=${SOURCE_ROOT}/confs$j
             FITNESS=$(cat $CONF/fitness.txt)
             if [ $FITNESS = ${OLD_FITNESS_SORT[$((i-1))]} ]; then
                 NEW_INDIVIDUALS[$IND]=$CONF
                 unset oldset[$((j-1))]
                 let IND+=1
                 break
             fi
         done
 
         for j in ${newset[@]}
         do
             OFF=${SOURCE_ROOT}/offs$j
             FITNESS=$(cat $OFF/fitness.txt)
             if [ $FITNESS = ${NEW_FITNESS_SORT[$((i-1))]} ]; then
                 NEW_INDIVIDUALS[$IND]=$OFF
                 unset newset[$((j-1))]
                 let IND+=1
                 break
             fi
         done
     done
     
     # make new individuals as parents and delete all others
     COUNT=1
     for path in ${NEW_INDIVIDUALS[@]}
     do
         TEMP=${SOURCE_ROOT}/TEMP$COUNT
         mkdir $TEMP
         cp $path/* $TEMP
         let COUNT+=1
     done
     for i in `seq 1 ${NUM_INDIVIDUALS}`
     do
         CONF=${SOURCE_ROOT}/confs$i
             rm -Rf $CONF
         OFF=${SOURCE_ROOT}/offs$i
         rm -Rf $OFF
         mv ${SOURCE_ROOT}/TEMP$i $CONF
     done
     unset OLD_FITNESS NEW_FITNESS NEW_INDIVIDUALS
}

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
rm -Rf confs* offs* Initial fit.log execution.log *.txt

for i in `seq 1 ${NUM_INDIVIDUALS}`
do
    CONF=${SOURCE_ROOT}/confs$i
        if [ ! -e $CONF ]; then
            mkdir -p $CONF
        fi
done

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

# Record all initial configurations
Record all
mkdir Initial; mv *txt Initial; cp -rn confs* Initial

# Begin evolution process
until (( $(echo "${BEST_FITNESS} <= $THRESHOLD" | bc -l) || $(echo "$SECONDS > $LIMIT" | bc -l) ))
do
    let ITERATION+=1
    echo "Iteration $ITERATION"

    # Step 3: Select best individuals (string) -- tournament selection
    INDIVIDUALS=$(Selection)
    echo "BEST INDIVIDUALS: ${INDIVIDUALS}"

    # Step 4: Crossover | Crossmix
    for i in `seq 1 2 ${NUM_INDIVIDUALS}`
    do
        IND1=`echo $INDIVIDUALS | awk -v ind=$i '{print $ind}'` # parent 1 index
        IND2=`echo $INDIVIDUALS | awk -v ind=$((i+1)) '{print $ind}'` # parent 2 index
        echo "Apply Crossover for individuals $IND1 and $IND2..."
        
        CONF1=${SOURCE_ROOT}/confs$IND1
        CONF2=${SOURCE_ROOT}/confs$IND2

        OFF1=${SOURCE_ROOT}/offs$i
        OFF2=${SOURCE_ROOT}/offs$((i+1))
    
        # first reserve offsprings
        mkdir -p $OFF1 $OFF2
        cp $CONF1/* $OFF1
        cp $CONF2/* $OFF2
         
        # Apply crossover to all config files 
        for file in `ls $OFF1/*.inc | xargs -n 1 basename`
        do
            Crossover $OFF1/$file $OFF2/$file
        done          
    done

    # Step 5: Mutation
    for i in `seq 1 ${NUM_INDIVIDUALS}`
    do
    CONF=${SOURCE_ROOT}/offs$i
        Mutate $CONF
    done  

    # Step 6: Fitness re-valuation
    for i in `seq 1 ${NUM_INDIVIDUALS}`
    do
        OFF=${SOURCE_ROOT}/offs$i
        echo "Re-calculation of fitness $i..."
        FITNESS=$(Fitness $OFF)
        echo $FITNESS > $OFF/fitness.txt
        cat $OFF/fitness.txt
    done

    # Step 7: Make a new generation
    Replace_sort

    # Update the best fitness function of the population
    BEST_FITNESS=$(echo $(Best) | cut -d " " -f 2)
    echo -e "$ITERATION \t ${BEST_FITNESS}" >> fit.log
 
    # Resume fitness values
    echo "Fitness values for Iteration $ITERATION"
    Resume
    echo $SECONDS >> execution.log
    
    # Record best generation
    Record best
done

rm zapped_channels.inc padding.inc integration_steps.inc
END=$(date +%s.%N) # end time

DIFF=$(echo "$END - $START" | bc) # duration
echo "Total execution time: ${DIFF} sec" 
