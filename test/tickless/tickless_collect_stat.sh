#!/bin/bash

if [ -n "$1" ] && [ -n "$2" ] ; then
	TIMER_INT=$1
	RUN_TIME=$2
	TOTAL_CPU=$(cat /proc/cpuinfo  | grep processor | wc -l)

	INITIAL_INTS=$(cat /proc/interrupts | grep "$TIMER_INT:")
	echo $INITIAL_INTS

	INT_COULMN=$(cat /proc/interrupts | grep -m 1 -n "$TIMER_INT:" | cut -d':' -f1)
	#mpstat adds a time column so add 1"
	INT_COULMN=$(( $INT_COULMN + 1 ))

	for (( i = 0 ; i < $RUN_TIME; i++ ))
	do
		mpstat  -I CPU 1 1 | grep '^Average' | awk -v a=$INT_COULMN '{print $2, $a}' >> timer_stat
	done

	FINAL_INTS=$(cat /proc/interrupts | grep "$TIMER_INT:")
	echo $FINAL_INTS

	echo "Total number of timer interrupts for the entire test duration:"
	for (( i = 0; i < $TOTAL_CPU; i++ ))
	do
		start_int=$(echo $INITIAL_INTS | awk -v a=$(( $i + 2 )) '{print $a}')
		stop_int=$(echo $FINAL_INTS | awk -v a=$(( $i + 2 )) '{print $a}')
		total_int=$(( $stop_int - $start_int))
		echo "CPU $i: $total_int"
	done
else
	echo "Pass the timer interrupt number as arg1 and time in seconds to collect interrupt statistics as arg2"
	exit 1
fi
