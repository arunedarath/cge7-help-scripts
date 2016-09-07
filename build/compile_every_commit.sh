#!/bin/bash

error_exit()
{
	echo "$1"
	echo "Exiting .."
	exit 1
}

record_starting_point()
{
	branch_str=$(git branch | grep ^*)
	detached=$(echo $branch_str | grep -c "(detached from *.*)")
	if [ $detached -eq 1 ] ; then
		echo "Starting test not in a git branch"
		CURRENT_BRANCH=
		DETACHED_HEAD=$(git log --pretty=oneline -1 HEAD | cut -d' ' -f1)
	else
		CURRENT_BRANCH=$(git branch | grep ^* | cut -d' ' -f2)
	fi
}

return_to_starting_point()
{
	if [ -n "$CURRENT_BRANCH" ] ; then
		echo "Returning to git branch:$CURRENT_BRANCH"
		git checkout $CURRENT_BRANCH > /dev/null
	else
		echo "Returning to starting commit:$DETACHED_HEAD"
		git checkout $DETACHED_HEAD
	fi
}

check_param_is_git_commit()
{
	param_in=$1

	git show $param_in > /dev/null
	rc=$?
	if [ $rc -eq 0 ] ; then
		param_val=$(git log --pretty=oneline -1 $param_in | cut -d' ' -f1)
		if [ "${param_val:0:7}" != "${param_in:0:7}" ] ; then
			error_exit "user passed param $param_in is not a git commit object"
		fi
	else
		echo "Passed param "$param_in" is not a git commit ID"
		error_exit "Please pass commit ID from where you want to start the test"
	fi
}

git_commits_to_test()
{
	commits_for_test=$(git log --pretty=oneline "$TEST_START_COMMIT""^..""$TEST_END_COMMIT" | cut -d' ' -f1 | tac)
}

tool_chain_to_use()
{

	if [ "$TC_MAIN_PATH" == "Custom" ] ; then
		return
	fi

	config=$1
	arch=$2

	endian=$(grep -c "CONFIG_CPU_BIG_ENDIAN=y" configs/$config)
	if [ "$endian" -eq 1 ] ; then
		endian="BE"
	else
		endian="LE"
	fi

	if [ "$arch" == "arm" ] ; then
		isa=$(grep -c "CONFIG_CPU_V7=y" configs/$config)
		if [ "$isa" -eq 1 ] ; then
			isa="V7"
			if [ "$endian" == "LE" ] ;then
				TC_TOP_DIR="arm-gnu"
			else
				TC_TOP_DIR="armeb-gnu"
			fi
		else
			isa="V6"
			if [ "$endian" == "LE" ] ;then
				TC_TOP_DIR="armv6-gnu"
			else
				TC_TOP_DIR="armv6eb-gnu"
			fi
		fi

	elif [ "$arch" == "arm64" ] ; then
		if [ "$endian" == "LE" ] ;then
			TC_TOP_DIR="armv8-gnu"
		else
			TC_TOP_DIR="armv8be-gnu"
		fi
	elif [ "$arch" == "x86" ] || [ "$arch" == "x86_64" ] ; then
		TC_TOP_DIR="x86_64-gnu"
	elif [ "$arch" == "powerpc" ] ; then
		temp=$(grep -wc "CONFIG_PPC_E500MC=y" configs/$config)
		if [ "$temp" -eq 1 ] ; then
			TC_TOP_DIR="powerpc64-gnu"
		else
			temp=$(grep -wc "CONFIG_E500=y" configs/$config)
			if [ "$temp" -eq 1 ] ; then
				TC_TOP_DIR="powerpc-gnu"
			else
				TC_TOP_DIR="powerpc32-nfp-gnu"
			fi
		fi
	elif [ "$arch" == "mips" ] ; then
		if [ "$endian" == "LE" ] ;then
			TC_TOP_DIR=
		else
			TC_TOP_DIR="mipseb-gnu"
		fi
	fi


	#for configs that don't follow the above rules
	if [ "$config" == "cavium-thunder-32_defconfig" ] ; then
		if [ "$endian" == "LE" ] ;then
			TC_TOP_DIR="aarch64-gnu"
		else
			TC_TOP_DIR="aarch64_be-gnu"
		fi
	fi

	if [ -z "$TC_TOP_DIR" ] ; then
		echo  "Unable to find the toolchain top dir for $config"
		CROSS_TC=
	else
		TC_PATH="$TC_MAIN_PATH"
		TC_PATH+="$TC_TOP_DIR"

# mips has two gccs in the toolchain directory mips64-octeon-linux-gnu-gcc and
# mipsisa64-octeon-elf-gcc this confuses the below logic so hardcode it to
# mips64-octeon-linux-gnu-gcc for mips
		if [ "$arch" == "mips" ] ; then
			TC="$TC_PATH/bin/mips64-octeon-linux-gnu-gcc"
			if [ ! -f "$TC" ] ; then
				TC=
			fi
		else
			TC=$(find "$TC_PATH/bin" | grep '.*.-gcc$')
		fi

		if [ -z "$TC" ] ; then
			echo  "Unable to find the cross gcc in $TC_PATH/bin"
			CROSS_TC=
		else
			CROSS_TC=$(echo $TC | rev | cut -d- -f2- | rev)
			CROSS_TC+="-"
		fi
	fi
}

identify_the_arch()
{
	config=$1
	if [ -f "configs/$config" ] ; then
		if [ $(grep -c -m 1 "^CONFIG_ARM64=y" configs/$config) -eq 1 ] ;then
			COMPILE_ARCH=arm64
		elif [ $(grep -c -m 1 "^CONFIG_ARM=y" configs/$config) -eq 1 ] ;then
			COMPILE_ARCH=arm
		elif [ $(grep -c -m 1 "^CONFIG_X86_32=y" configs/$config) -eq 1 ] ;then
			COMPILE_ARCH=x86
		elif [ $(grep -c -m 1 "^CONFIG_X86_64=y" configs/$config) -eq 1 ] ;then
			COMPILE_ARCH=x86_64
		elif [ $(grep -c -m 1 "^CONFIG_PPC32=y" configs/$config) -eq 1 ] ;then
			COMPILE_ARCH=powerpc
		elif [ $(grep -c -m 1 "^CONFIG_MIPS=y" configs/$config) -eq 1 ] ;then
			COMPILE_ARCH=mips
		fi

		if [ -z "$COMPILE_ARCH" ] ; then
			echo "Unable to find the architecture for $config"
		else
			if [ "$COMPILE_ARCH" == "arm" ] ; then
				MAKE_TARGET=Image
			elif [ "$COMPILE_ARCH" == "arm64" ] ; then
				MAKE_TARGET=Image
			elif [ "$COMPILE_ARCH" == "x86" ] ; then
				MAKE_TARGET=bzImage
			elif [ "$COMPILE_ARCH" == "x86_64" ] ; then
				MAKE_TARGET=bzImage
			elif [ "$COMPILE_ARCH" == "powerpc" ] ; then
				MAKE_TARGET=zImage
			elif [ "$COMPILE_ARCH" == "mips" ] ; then
				MAKE_TARGET=vmlinux
			fi
		fi

		tool_chain_to_use $config $COMPILE_ARCH
	else
		echo "The given config $config is not there inside configs directory"
		echo "Please pass the right defconfig file"
		COMPILE_ARCH=
	fi
}

check_if_num()
{
	param="$1";

	num='^[0-9]+$'
	if [[ $param =~ $num ]] ; then
		IT_IS_NUMBER="yes"
	else
		IT_IS_NUMBER="no"
	fi
}

select_all_configs_for_test()
{
	configs_for_test=$(ls configs | sort)
}

usage()
{
	echo "Usage: compile_every_commit.sh [Options]"
	echo "Compile tests CGE7 kernel starting from a user specified commit ID for the requested configs"
	echo -e "\nEg: \$$0 -c <start commit ID> -d <configs to test> -o <test log file> -t <montavista toolchain installation dir>"
	echo -e "\nOptions:"
	echo -e "\t -c, git commit ID from where the compilation test will start"
	echo -e "\t -e, git commit ID to end the test"
	echo -e "\t -d, defconfigs for the compile test"
	echo -e "\t     User can test more than one defconfigs by separating them with space and using double quotes"
	echo -e "\t     Eg: \$$0 -d \"config1 config2 config3\""
	echo -e "\t -t, Directory where montavista toolchains are installed"
	echo -e "\t -o, Optional test log output file. If not specified logs will be saved in a default file"
	echo -e "\t -p, How many parallel make to perform. It ths passed to make as -j<param>"
	echo -e "\t -a, Select all configs in the 'configs' folder for testing"
	echo -e "\t -x, Pass a custom toolchain for the test"
	echo -e "\t -y, Pass the architecture here"
}

while getopts  "c:d:o:t:p:e:x:y:ah" OPTION
do
	case $OPTION in
	h)
		usage
		exit 0
		;;
	d)
		configs_for_test="$OPTARG"
		;;
	c)
		check_param_is_git_commit "$OPTARG"
		TEST_START_COMMIT="$OPTARG"
		;;
	e)
		check_param_is_git_commit "$OPTARG"
		TEST_END_COMMIT="$OPTARG"
		;;
	t)
#TC_MAIN_PATH  is the directory where your toolchains are installed
# $ls ~/montavista/cg7/tools/
# aarch64_be-gnu  armeb-gnu  arm-gnu  armv6-gnu  armv8be-gnu  armv8-gnu  mipseb-gnu  x86_64-gnu
		TC_MAIN_PATH="$OPTARG"
		;;
	o)
		COMPILE_TEST_LOG="$OPTARG"
		;;
	p)
		check_if_num $OPTARG
		if [ "$IT_IS_NUMBER" == "yes" ] ; then
			PARALLEL_MAKE="$OPTARG"
		else
			echo "Parallel make parameter passed is not a number, setting it to 8"
			PARALLEL_MAKE="8"
		fi
		;;
	a)
		select_all_configs_for_test
		;;
	x)
		echo "Got a custom tc"
		TC_MAIN_PATH="Custom"
		CROSS_TC="$OPTARG"
		;;
	y)
		COMPILE_ARCH="$OPTARG"
		MAKE_TARGET=Image
		;;
	?)
		usage
		error_exit
		;;
	esac
done

# Start with the parameter check
if [ -z "$TEST_START_COMMIT" ] ; then
	echo "Testing compilation for HEAD!!!!!!!!!!!!!!"
	TEST_START_COMMIT=$(git log --pretty=oneline  -1 | cut -d' ' -f1)
	TEST_END_COMMIT=$TEST_START_COMMIT
fi

if [ -z "$TEST_END_COMMIT" ] ; then
	echo "Taking HEAD as the end commit"
	TEST_END_COMMIT=$(git log --pretty=oneline  -1 | cut -d' ' -f1)
fi

if [ -z "$configs_for_test" ] ; then
	error_exit "No configs are selected for testing"
fi

git_commits_to_test

if [ -z "$commits_for_test" ] ; then
	error_exit "Missing test start commit ID"
fi

if [ -z "$TC_MAIN_PATH" ] ; then
	error_exit "You did not specify the toolchain path. I can't do compilation without a cross toolchain"
fi

if [ -z "$PARALLEL_MAKE" ] ; then
	num_cores=$(nproc)
	PARALLEL_MAKE="$num_cores"
	echo "Using number of cores($PARALLEL_MAKE) as argument for parallel make"
fi

if [ -z "$COMPILE_TEST_LOG" ] ; then
	log_file="compile_test_commits_"
	log_file+=$(date +"%a %b %d %T %Y" | tr " " _ | tr ":" _ | tr '[:upper:]' '[:lower:]')
	log_file+="_log_"
	log_file+="$RANDOM"
	COMPILE_TEST_LOG="$log_file"
fi

record_starting_point
echo "start" > "$COMPILE_TEST_LOG"
echo "---" >> "$COMPILE_TEST_LOG"

#start the test
for config in `echo $configs_for_test`
do
	COMPILE_CONFIG="$config"

	if [ -z "$COMPILE_ARCH" ] ; then
		identify_the_arch $COMPILE_CONFIG
	fi

	if [ -n "$COMPILE_ARCH" ]  && [ -n "$CROSS_TC" ] ; then
		echo "~~~~~~~~~~~~~~~~~~~~~~~ compiling $COMPILE_CONFIG ~~~~~~~~~~~~~~~~~~~~~~~~"
		echo "Cross toolchain used: $CROSS_TC" >> "$COMPILE_TEST_LOG"
		for commit in `echo $commits_for_test`
		do
			git checkout $commit > /dev/null 2>&1
			COMMIT_MSG=$(git log --pretty=oneline -1 $commit)
			echo -e "\ntesting ==> $COMMIT_MSG"

			cp configs/$COMPILE_CONFIG .config
			yes "" | make ARCH=$COMPILE_ARCH oldconfig > /dev/null 2>&1

			make ARCH=$COMPILE_ARCH CROSS_COMPILE="$CROSS_TC" $MAKE_TARGET -j$PARALLEL_MAKE > /dev/null
			rc=$?
			if [ $rc -ne 0 ] ; then
				echo "Compiling again to make sure that it is a failure; not a temporary license error"
				make ARCH=$COMPILE_ARCH CROSS_COMPILE="$CROSS_TC" $MAKE_TARGET -j$PARALLEL_MAKE > /dev/null
				rc=$?
			fi

			if [ $rc -ne 0 ] ; then
				echo "compilation failed for $COMPILE_CONFIG $COMMIT_MSG"
				echo "FAILED: $COMPILE_CONFIG $COMMIT_MSG" >> "$COMPILE_TEST_LOG"
			else
				echo "SUCCESS: $COMPILE_CONFIG $COMMIT_MSG" >> "$COMPILE_TEST_LOG"
			fi
		done
		echo "~~~~~~~~~~~~~~~~~~~~~~~ finished compiling $COMPILE_CONFIG ~~~~~~~~~~~~~~~~~~~~~~~~"
		echo "---" >> "$COMPILE_TEST_LOG"
	else
		echo "Something wrong didn't perform test for $COMPILE_CONFIG" >> "$COMPILE_TEST_LOG"
		echo "---" >> "$COMPILE_TEST_LOG"
	fi
done

echo "end" >> "$COMPILE_TEST_LOG"
return_to_starting_point
echo ""
echo '$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$'
echo "Test results are saved in file $COMPILE_TEST_LOG"
echo '$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$'
echo ""
