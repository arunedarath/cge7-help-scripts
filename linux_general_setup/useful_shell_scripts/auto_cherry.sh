usage () {
	echo "Usage: auto_cherry.sh [Options]"
	echo "If you are cherry-picking a bunch of commits, use auto_cherry.sh to make it easy"
	echo -e "\nEg: \$$0 -f <commit_series_file> -b <bug number>"
	echo -e "\nOptions:"
	echo -e "\t-f, The file containg the commits. It only takes one commits per line
       	 If you have 10 commits to cherry-pick the series file should have 10 lines, with each git commit IDs forming a line.
	 The commits should be arranged in the order in which they needs to be cherry-picked"
	echo -e "\t-b, The bugID"
	exit 1
}

while getopts  "f:b:h" OPTION
do
	case $OPTION in
	h)
		usage
		exit 1
		;;
	f)
		commit_series_file=$OPTARG
		if [ ! -f "$commit_series_file" ] ; then
			echo "$commit_series_file is not a commit series file"
			echo "-f needs a commit series file as the argument"
			usage
		else
			echo "Using $commit_series_file as the commit series"
			COMMIT_LOG="$commit_series_file""_auto_cherry_commit_log"
		fi

		if [ -f $COMMIT_LOG ] ; then
			echo "Using the already existing $COMMIT_LOG file"
		else
			echo "Creating new commit file $COMMIT_LOG"
			cat $commit_series_file | sed -e 's/$/& [apply]/g' > $COMMIT_LOG
		fi

		;;
	b)
		BUG="$OPTARG"
		;;
	?)
		usage
		exit
		;;
	esac
done

if [ -z $COMMIT_LOG ] ; then
	echo "please pass the commit series file using -f option"
	usage
fi

if [ -z "$BUG" ] ; then
	echo "please pass the bug number using -b option"
	usage
fi

SOURCE="kernel.org"
MSG="Backport from"
TYPE="Integration"

total_lines=$(wc -l $COMMIT_LOG | cut -d' ' -f1)
line_no=0

echo "Total no of commits to process: $total_lines"
while read line <&3
do
	line_no=$((line_no + 1 ))
	APPLY=$(echo $line | cut -d' ' -f2 | sed -e 's/\[//' -e 's/\]//')
	if [ $APPLY == "apply" ] ; then
		COMMIT_ID=$(echo $line | cut -d' ' -f1)
		DISC=$(git describe --contains $COMMIT_ID | cut -d~ -f1)

		echo "Cherry-picking $COMMIT_ID"
		git-cherry-pick-mv --bugz $BUG --source "$SOURCE" --disposition "$MSG $DISC" --type "$TYPE" $COMMIT_ID

		if [ $? -ne 0 ] ; then
			echo -e "\nAttention cherry-pick failed for $COMMIT_ID"
			sed -i "$line_no""s/\[apply\]/\[failed\]/" $COMMIT_LOG
			break
		else
			sed -i "$line_no""s/\[apply\]/\[applied\]/" $COMMIT_LOG
		fi
	else
		COMMIT_ID=$(echo $line | cut -d' ' -f1)
		echo "No action to do for $COMMIT_ID; It said $line"
	fi
done 3<"$COMMIT_LOG"

echo "processed = $line_no"
exit 0
