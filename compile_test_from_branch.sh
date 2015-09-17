#!/bin/bash
#configs_for_test is formed as given below
#configs_to_test:montavista_tool_chain_top_dir:make_target

configs_for_test="
apm-mustang-xgene_defconfig:armv8be-gnu
freescale-ls1043a_defconfig:armv8-gnu
cavium-thunder-32_defconfig:aarch64_be-gnu"


#TC_MAIN_PATH  is the directory where your toolchains are installed
# $ls ~/montavista/cg7/tools/
# aarch64_be-gnu  armeb-gnu  arm-gnu  armv6-gnu  armv8be-gnu  armv8-gnu  mipseb-gnu  x86_64-gnu

TC_MAIN_PATH="/home/arun/montavista/cg7/tools/"

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
		if [ "${param_val:0:7}" == "${param_in:0:7}" ] ; then
			TEST_START_COMMIT=$param_in
			commits_for_test=$(git log --pretty=oneline $TEST_START_COMMIT^.. | cut -d' ' -f1 | tac)
		else
			error_exit "user passed param $param_in is not a git commit object"
		fi
	else
		echo "Passed param "$param_in" is not a git commit ID"
		error_exit "Please pass commit ID from where you want to start the test"
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
				MAKE_TARGET=Image
			elif [ "$COMPILE_ARCH" == "mips" ] ; then
				MAKE_TARGET=Image
			fi
		fi
	else
		echo "The given config $config is not there inside configs directory"
		echo "Please pass the right defconfig file"
		COMPILE_ARCH=
	fi
}

# Start with the parameter check
if [ -n "$1" ] ; then
	check_param_is_git_commit $1
	record_starting_point
else
	error_exit "Please pass commit ID from where you want to start the test"
fi

COMPILE_TEST_LOG="compile_test_commits_log"
echo "start" > "$COMPILE_TEST_LOG"

#start the test
for config in `echo $configs_for_test`
do
	TC_PATH="$TC_MAIN_PATH"
	TC_PATH+=$(echo $config | cut -d: -f2)
	TC=$(find "$TC_PATH/bin" | grep '.*.-gcc$')

	if [ -z "$TC" ] ; then
		error_exit "Unable to find the toolchain for compiling $config"
	fi

	CROSS_TC=$(echo $TC | rev | cut -d- -f2- | rev)

	COMPILE_CONFIG=$(echo $config | cut -d: -f1)

	identify_the_arch $COMPILE_CONFIG

	if [ -n "$COMPILE_ARCH" ] ; then
		echo "################ compiling $COMPILE_CONFIG #####################"

		for commit in `echo $commits_for_test`
		do
			echo -e "\n------ testing $(git log --pretty=oneline -1 $commit) --------\n"
			git checkout $commit > /dev/null 2>&1
			cp configs/$COMPILE_CONFIG .config
			yes "" | make ARCH=$COMPILE_ARCH oldconfig > /dev/null 2>&1
			make ARCH=$COMPILE_ARCH CROSS_COMPILE="$CROSS_TC-" $MAKE_TARGET -j8 > /dev/null
			if [ $? -ne 0 ] ; then
				FAIL_COMMIT=$(git log --pretty=oneline -1 HEAD | cut -d' ' -f1-)
				echo "compilation failed for $COMPILE_CONFIG $FAIL_COMMIT"
				echo "FAILED: $COMPILE_CONFIG $FAIL_COMMIT" >> "$COMPILE_TEST_LOG"
			else
				PASS_COMMIT=$(git log --pretty=oneline -1 HEAD | cut -d' ' -f1-)
				echo "SUCCESS: $COMPILE_CONFIG $PASS_COMMIT" >> "$COMPILE_TEST_LOG"
			fi
		done
		echo "---" >> "$COMPILE_TEST_LOG"
	fi
done

echo "end" >> "$COMPILE_TEST_LOG"
return_to_starting_point
