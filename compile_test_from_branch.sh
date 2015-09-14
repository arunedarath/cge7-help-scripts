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

if [ -n "$1" ] ; then
	git show $1 > /dev/null
	rc=$?
	if [ $rc -ne 0 ] ; then
		echo "Please pass a git commit "
		exit 1
	else
		TEST_START_COMMIT=$1
		commits_for_test=$(git log --pretty=oneline $TEST_START_COMMIT.. | cut -d' ' -f1 | tac)
		CURRENT_BRANCH=$(git branch | grep ^* | cut -d' ' -f2)
	fi
else
	echo "Please pass from where you want to start the test"
	exit 1
fi

COMPILE_TEST_LOG="compile_test_commits_log"
echo "start" > "$COMPILE_TEST_LOG"

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
