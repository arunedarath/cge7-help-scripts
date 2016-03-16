#!/bin/bash

make_test_dir()
{
	tmp="read_write_io_"
	tmp+=$(date | tr " " _)
	tmp+="_""$RANDOM"
	TEST_DIR="$TEST_DRIVE""/""$tmp"
	mkdir $TEST_DIR
}

if [ -z "$1" ] ; then
	echo "please pass the mount directory to test as arg1"
	echo "Eg: read_write_io_performance.sh /media/sdb1"
	exit 1
else
	if [ -d $1 ] ; then
		TEST_DRIVE=$(readlink -f $1)
		make_test_dir
	else
		echo "Arg1 = $1 is not a directory"
		echo "Please pass a the directory where the device is mounted"
		exit 1
	fi
fi

# To be used with devices that has read speed more that write speed
achieve_mb_per_sec_write_speed()
{
	#start with BS = 4K
	BS=4
	MAX_SIZE=$(( 1024 * 10 ))

	echo "Trying to find a block size that give more than 1MB/sec read/write speeds"
	file_name="mb_per_sec_write_speed"
	while true
	do
		CNT=$(( $MAX_SIZE / $BS ))

		if [ $BS -gt 1024 ] ; then
			echo "Unable to achive 1MB/sec with block sizes less than 1MB; exiting"
			exit 1
		else
			echo "Testing with bs=$BS""KB and count = $CNT"
		fi

		tmp=0
		for (( i = 0; i < 5; i++ ))
		do
			tmp=$(( $tmp + $(dd if=/dev/zero of=$file_name bs="$BS""K" count=$CNT oflag=sync 2>&1 | grep -c "MB/s") ))
		done

		if [ $tmp -eq $i ] ; then
			echo "Achieved MB/sec with bs=$BS""KB and count = $CNT"
			break;
		fi

		BS=$(( $BS * 2 ))
	done
}


cd $TEST_DIR
achieve_mb_per_sec_write_speed
# Save the BS that achieved MB/sec
BS_MB_SEC=$BS

#Max test file size = 1048576KB = 1G
TEST_FILEMAX_SIZE=1048576
#Max test file size = 2048KB = 2M
TEST_FILEMIN_SIZE=2048
TEST_FILE_SIZE=$TEST_FILEMIN_SIZE

#How many samples to take average value
SAMPLES=10

while true
do
	if [ $TEST_FILE_SIZE -gt $TEST_FILEMAX_SIZE ] ; then
		echo "Read write IO test finished"
		break
	fi

	echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
	echo "Testing r/w: file size = $TEST_FILE_SIZE""KB"
	echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

	BS=$TEST_FILE_SIZE
	CNT=1

	while [ $BS -ge $BS_MB_SEC ]
	do
		echo "Performing dd with BS= $BS count = $CNT"

		write_result_str=
		read_result_str=
		file_name="test_file_read_write_io"
		for (( i = 0; i < $SAMPLES ; i++ ))
		do
			write_result_str+=$(dd if=/dev/zero of=$file_name bs="$BS""K" count=$CNT oflag=sync 2>&1 | tail -1 | cut -d, -f3)
			read_result_str+=$(dd if=$file_name of=/dev/null iflag=nocache 2>&1 | tail -1 | cut -d, -f3)
		done

		avg_write_speed=0.0
		mb_per_sec=$(echo $write_result_str | grep -o "MB/s" | wc -l)
		if [ $mb_per_sec -ne $SAMPLES ] ; then
			echo "Not all values in MB/s; skipping AVG calculation for write speed"
		else
			total=0.0
			str=$(echo $write_result_str | sed -e 's/MB\/s//g')
			for speed in $str
			do
				total=$(echo "$speed + $total" | bc)
			done
			avg_write_speed=$(echo "$total / $SAMPLES" | bc -l)
		fi

		avg_read_speed=0.0
		mb_per_sec=$(echo $read_result_str | grep -o "MB/s" | wc -l)
		if [ $mb_per_sec -ne $SAMPLES ] ; then
			echo "Not all values in MB/s; skipping AVG calculation for read speed"
		else
			total=0.0
			str=$(echo $read_result_str | sed -e 's/MB\/s//g')
			for speed in $str
			do
				total=$(echo "$speed + $total" | bc)
			done
			avg_read_speed=$(echo "$total / $SAMPLES" | bc -l)
		fi

		echo "write result = $write_result_str"
		echo "read result = $read_result_str"
		echo "AVG write speed = $avg_write_speed AVG read speed = $avg_read_speed"
		echo ""

		BS=$(( $BS / 2 ))
		CNT=$(( $CNT * 2 ))
	done

	TEST_FILE_SIZE=$(( $TEST_FILE_SIZE * 2 ))
done
