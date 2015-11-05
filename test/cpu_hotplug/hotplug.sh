#!/bin/bash

make_all_cpu_online()
{
	for cpu in $(seq 1 $(( $TOTAL_CPU - 1 )))
	do
		grep -q 1 /sys/devices/system/cpu/cpu$cpu/online
		rc=$?
		#cpu is offline if not zero
		if [ $rc -ne 0 ] ; then
			echo 1 >/sys/devices/system/cpu/cpu$cpu/online
			rc=$?
			if [ $rc -ne 0 ] ; then
				echo "Failed onlining $cpu"
			fi
		fi
	done
}

if [ -n "$1" ] ; then
	TOTAL_CPU=$1
	#Use a stress count 4 times number of cpus
	STRESS_COUNT=$(( $TOTAL_CPU * 4 ))
	ST=$SECONDS

	#start stressing
	stress -c $STRESS_COUNT &
	rc=$?
	if [ $rc -ne 0 ] ; then
		echo "Failed to start stress"
		exit 1
	fi
	echo "----------------- CPU hotplug test starting ---------------------"
	#Make all CPUs online
	echo "Making all CPUs online"
	make_all_cpu_online

	if [ -n "$2" ] ; then
		TOTAL_TEST_DURATION_SEC="$2"
		echo "Will do hotplug test for $TOTAL_TEST_DURATION_SEC seconds"
	else
		echo "Not specified the test duration\; will run for 1 hour"
		TOTAL_TEST_DURATION_SEC="3600"
	fi
else
	echo "Pass number of CPU as argument 1"
	exit 1
fi

test_itr=1
while true
do
	echo "~~~~~~~~~~"
	echo "Testing $test_itr"
	echo "~~~~~~~~~~"
	RUN_TIME=$(( $SECONDS - $ST ))
	if [ $RUN_TIME -ge $TOTAL_TEST_DURATION_SEC ] ; then
		echo "Ran the test for $TOTAL_TEST_DURATION_SEC seconds. Stopping" 
		killall stress
		break;
	fi

	#Randomely makes CPUs (except cpu 0) offline and online. Each iteration also chooses random
	#number of cpus to make offline/online.
	cpu_list=$(seq 1  $(( $TOTAL_CPU - 1 )) | sort -R)
	off_line_cpu_count=$(echo $cpu_list | awk '{print $1}')
	cpu_list=$(seq 1  $(( $TOTAL_CPU - 1 )) | sort -R)

	off_line_list=
	for (( i=1; i<=$off_line_cpu_count; i++ ))
	do
		off_line_list+=" $(echo $cpu_list | awk -v a=$i '{print $a}')"
	done

	# Make the members of off_line_list offline
	echo "Offlining CPUS:$(echo $off_line_list | tr '\n' ' ')"
	for cpu in $off_line_list
	do
		echo 0 >/sys/devices/system/cpu/cpu$cpu/online
		rc=$?
		if [ $rc -ne 0 ] ; then
			echo "Failed offlining $cpu"
		fi
	done

	# Display the stat of online CPUs for the last second"
	echo -e "stat of online CPUs:\n$(mpstat -u -P ON 1 1 | grep 'Average')\n"

	# Make the members of off_line_list back to online
	for cpu in $off_line_list
	do
		echo 1 >/sys/devices/system/cpu/cpu$cpu/online
		rc=$?
		if [ $rc -ne 0 ] ; then
			echo "Failed onlining $cpu"
		fi
	done

	# Display the stat of online CPUs for the last second"
	echo -e "stat of all CPUs:\n$(mpstat -u -P ON 1 1 | grep 'Average')"
	test_itr=$(( $test_itr + 1 ))
done
