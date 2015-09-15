#!/bin/bash
#configs_for_test is formed as given below
#configs_to_test:config_arch:montavista_tool_chain_top_dir:make_target

configs_for_test="
apm-mustang-xgene_defconfig:arm64:armv8be-gnu:Image
freescale-ls1043a_defconfig:arm64:armv8-gnu:Image
cavium-thunder-32_defconfig:arm64:aarch64_be-gnu:Image"

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
			CURRENT_BRANCH=$(git branch | grep ^* | cut -d' ' -f2)
		else
			error_exit "user passed param $param_in is not a git commit object"
		fi
	else
		echo "Passed param "$param_in" is not a git commit"
		error_exit "Please pass commit ID from where you want to start the test"
	fi
}

# Start with the parameter check
if [ -n "$1" ] ; then
	check_param_is_git_commit $1
else
	error_exit "Please pass commit ID from where you want to start the test"
fi

COMPILE_TEST_LOG="compile_test_commits_log"
echo "start" > "$COMPILE_TEST_LOG"

#start the test
for config in `echo $configs_for_test`
do
	TC_PATH="$TC_MAIN_PATH"
	TC_PATH+=$(echo $config | cut -d: -f3)
	TC=$(find "$TC_PATH/bin" | grep '.*.-gcc$')

	if [ -z "$TC" ] ; then
		echo "Unable to find the toolchain for compiling $config"
		exit 1
	fi

	CROSS_TC=$(echo $TC | rev | cut -d- -f2- | rev)
	COMPILE_CONFIG=$(echo $config | cut -d: -f1)
	COMPILE_ARCH=$(echo $config | cut -d: -f2)
	MAKE_TARGET=$(echo $config | cut -d: -f4)

	if [ -f "configs/$COMPILE_CONFIG" ] ; then
		echo "################ compiling $COMPILE_CONFIG #####################"

		for commit in `echo $commits_for_test`
		do
			echo -e "\n------ testing $(git log --pretty=oneline -1 $commit) --------\n"
			git checkout $commit
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
	else
		echo "$COMPILE_CONFIG is not found inside configs"
	fi
done

git checkout $CURRENT_BRANCH
