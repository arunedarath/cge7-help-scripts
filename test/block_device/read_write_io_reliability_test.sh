#!/bin/bash

verify_mount_point()
{
	rc="-1"
	if [ -d $1 ] ; then
		TEST_DRIVE=$(readlink -f $1)
		if [ $(mount | grep -c -w "$TEST_DRIVE") -eq 1 ] ; then
			str=$(mount | grep -w "$TEST_DRIVE")
			mount_point=$(echo $str | cut -d' ' -f3)

			if [ "$mount_point" == "$TEST_DRIVE" ] ; then
				rc="0"
			fi
		fi
	fi

	if [ "$rc" == "-1" ] ; then
		echo "Passed arg1 = $1 is not the topmost mount point"
		echo -e "The current valid mount points in your system are \n$(mount | cut -d' ' -f3)"
		echo "Please pass a valid mount point"
	fi
}

make_test_dir()
{
	test_dir="rw_io_rel_test_"
	test_dir+=$(date +"%a %b %d %T %Y" | tr " " _ | tr ":" _ | tr '[:upper:]' '[:lower:]')
	test_dir+="_""$RANDOM"
	TEST_DIR="$TEST_DRIVE""/""$test_dir"
	mkdir $TEST_DIR
}

make_tmp_test_folder()
{
	TMP_TEST_DIR="/tmp/""$test_dir""/"
	mkdir $TMP_TEST_DIR
}

calculate_max_file_size()
{
	available_kb=$(df $TEST_DRIVE | tail -1 | awk '{print $4}')

	#Set the max file size to one fourth of available size"
	TEST_FILEMAX_SIZE=$(( $available_kb / 4 ))

	#Min test file size = 512KB
	TEST_FILEMIN_SIZE=512

	if [ $TEST_FILEMAX_SIZE -le $TEST_FILEMIN_SIZE ] ; then
		echo "Device:$TEST_DRIVE don't have enough available space for testing"
		echo "Exiting"
		exit 1
	fi

	echo "Test IO range in KB $TEST_FILEMIN_SIZE <= test_file_size <= $TEST_FILEMAX_SIZE"
}

do_the_test()
{
	TEST_FILE_SIZE=$TEST_FILEMIN_SIZE
	MIN_BLOCK_SIZE=64

	while true
	do
		if [ $TEST_FILE_SIZE -gt $TEST_FILEMAX_SIZE ] ; then
			echo "IO realiability test finished"
			exit 0
		fi

		echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
		echo "Testing... file size = $TEST_FILE_SIZE""KB"
		echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

		BS=$TEST_FILE_SIZE
		CNT=1

		while [ $BS -ge $MIN_BLOCK_SIZE ]
		do
			echo "Performing dd with BS = $BS count = $CNT"
			file_name="test_file_reliability_""$TEST_FILE_SIZE""_$BS""_$CNT"
			tmp_file_name="$TMP_TEST_DIR""$file_name"

			dd if=/dev/urandom of=$file_name bs="$BS""K" count=$CNT oflag=sync >/dev/null 2>&1
			md1=$(md5sum $file_name | cut -d' ' -f1)

			#now copy the image to /tmp and delete the disk copy
			cp $file_name $tmp_file_name
			rm $file_name

			#no calculate md5sum for /tmp copy
			md2=$(md5sum $tmp_file_name | cut -d' ' -f1)

			#Now copy back from /tmp to disk and remove /tmp copy
			cp $tmp_file_name "."
			rm $tmp_file_name

			#Calculate md5sum for copied file and remove it
			md3=$(md5sum $file_name | cut -d' ' -f1)
			rm $file_name

			#md1, md2 and md3 should be equal
			if [ "$md1" == "$md2" ] ; then
				if [ "$md1" == "$md3" ] ; then
					echo "Passed for $file_name"
				else
					echo "md3 failed for $file_name"
					exit 1
				fi
			else
				echo "md1 failed for $file_name"
				exit 1
			fi

			BS=$(( $BS / 2 ))
			CNT=$(( $CNT * 2 ))
		done

		TEST_FILE_SIZE=$(( $TEST_FILE_SIZE * 2 ))
	done
}

if [ -z "$1" ] ; then
	echo "please pass the mount directory to test as arg1"
	echo "Eg: read_write_io_reliability_test.sh /media/sdb1"
	exit 1
else
	verify_mount_point $1
	if [ $rc == "-1" ] ; then
		echo "Exiting without performing the test"
		exit 1
	fi

	calculate_max_file_size

	# Do test setup
	make_test_dir

	make_tmp_test_folder

	echo "CDing to $TEST_DIR"
	cd $TEST_DIR

	do_the_test
fi
