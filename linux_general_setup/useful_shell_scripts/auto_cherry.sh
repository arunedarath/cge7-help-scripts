usage () {
	echo -e "\nUsage: auto_cherry.sh <commit_series_file> <BUGID>"
	exit 1
}

if [ -n "$1" ]  && [ -n "$2" ] ; then
	if [ ! -f "$1" ] ; then
		echo "$1 is not a commit series file"
		echo "Please supply a commit series file as arg1 and BUGID as arg2"
		usage
	fi

	echo "Using $1 as the commit series"
	COMMIT_LOG=$1_auto_cherry_commit_log
	COMMIT_LOG_SAVE=$COMMIT_LOG"_save"
	if [ -f $COMMIT_LOG ] ; then
		echo "Using the already existing $COMMIT_LOG file"
	else
		echo "Creating new commit fiew $COMMIT_LOG"
		cat $1  | tac | sed -e 's/$/& [apply]/g' > $COMMIT_LOG
	fi
else
	usage
fi

BUG="$2"
SOURCE="kernel.org"
MSG="Backport from"
TYPE="Integration"

total_lines=$(wc -l $COMMIT_LOG | cut -d' ' -f1)
no_of_lines=0

echo "Total no of lines to process = $total_lines"
while read line <&3
do
	no_of_lines=$((no_of_lines + 1 ))
	APPLY=$(echo $line | cut -d' ' -f2 | sed -e 's/\[//' -e 's/\]//')
	if [ $APPLY == "apply" ] ; then
		COMMIT_ID=$(echo $line | cut -d' ' -f1)
		DISC=$(git describe --contains $COMMIT_ID | cut -d~ -f1)

		echo "using $COMMIT_ID"

		git-cherry-pick-mv --bugz $BUG --source "$SOURCE" --disposition "$MSG $DISC" --type "$TYPE" $COMMIT_ID

		if [ $? -ne 0 ] ; then
			echo -e "\nAttention cherry-pick failed for $COMMIT_ID"
			echo $line | sed -e 's/\[apply\]/\[failed\]/' >> $COMMIT_LOG_SAVE
			break
		else
			echo $line | sed -e 's/\[apply\]/\[applied\]/' >> $COMMIT_LOG_SAVE
		fi
	else
		echo "$line" >> $COMMIT_LOG_SAVE
	fi
done 3<"$COMMIT_LOG"

echo "processed = $no_of_lines"
no_of_lines=$((no_of_lines + 1 ))

sed -n $no_of_lines,$total_lines"p" $COMMIT_LOG >> $COMMIT_LOG_SAVE
mv $COMMIT_LOG_SAVE $COMMIT_LOG
exit 0
