The Apertif Monitor for Bursts Encountered in Real-time (AMBER, [1]) auto-tuning optimization with genetic algorithms. 

The program limits exploration of the total parameter space, finds more optimal configurations than brute-force tuning and reduces tuning time to 2-5 hours instead of 10. The code is dedicated to the Apertif Lofar Exploration of the Radio Transient Sky (ALERT, [2]) but can be easily ported to any other radio transient surveys.

defs.sh -- parameters of the survey 

performance_test.sh -- fitness function evaluation (pipeline processing time on randomly generated data)

ga_tuner.sh -- tuning with genetic search

random_tuner.sh -- tuning with random search

[1] https://github.com/AA-ALERT/AMBER/

[2] http://alert.eu/
