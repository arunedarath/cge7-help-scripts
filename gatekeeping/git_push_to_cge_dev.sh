usage()
{
	echo -e "\nUsage:"
	echo "	git_merge_to_dev_branch.sh <branch name to merge> <no of patches to merge>"
	exit 1
}

if [ -z "$1" ] || [ -z "$2" ] ; then
	echo "Please pass git branch to merge as arg1 and no of commits to merge as arg2"
	usage
fi

check_the_branch()
{
	tmp_br="origin/$1"
	is_br_uniq=$(git branch -r | grep -cw "$tmp_br")

	rc=$?

	if [ $rc -ne 0 ] ; then
		echo -e "\nThe branch $tmp_br is not seen when 'git branch -r is run'"
		echo -e "Please pass the correct name of bugfix branch"
		usage
	fi

	if [ $is_br_uniq -ne 1 ] ; then
		echo "The branch supplied "$1" seems to be incorrect"
		echo "Please pass the correct branch"
		usage
	fi

	merge_br="$tmp_br"
}

check_no_of_commits_to_merge()
{
        param="$1";

        num='^[0-9]+$'
        if ! [[ $param =~ $num ]] ; then
		echo "The number of commits is wrong"
		usage
        fi

	merg_commits="$param"
}

REPO_MERG_BR="mvl7-3.10/cge_dev"
ORIGIN_BR="origin/""$REPO_MERG_BR"
LOCAL_BR="local_""$REPO_MERG_BR""_$RANDOM"
create_local_merg_br()
{
	echo "Creating local branch \"$LOCAL_BR\""
	git checkout -b "$LOCAL_BR" "$ORIGIN_BR"
}

populate_local_br()
{
	for (( i=$(($merg_commits - 1)) ; i >= 0 ; i --))
	do
		cherry_commit=$(git log -1 --pretty=oneline "$merge_br""~$i" | cut -d' ' -f1)
		echo "Cherry-picking $(git log -1 --pretty=oneline $cherry_commit)"
		git cherry-pick -s "$cherry_commit"
		rc=$?

		if [ $rc -ne 0 ] ; then
			echo "Git cherry-pick failed; Please verify the changes; exiting"
			exit 1
		fi
	done
}

update_the_repo()
{
	echo "Updating the remote branches"
	git fetch origin
	rc=$?

	if [ $rc -ne 0 ] ; then
		echo "Something is wrong; Seems git fetch is not working; exiting"
		exit 1
	fi
}

update_the_repo
check_the_branch $1
check_no_of_commits_to_merge $2

echo "The branch for merge:$merge_br; no of commits:$merg_commits"

create_local_merg_br
populate_local_br

echo "Will push $LOCAL_BR to $REPO_MERG_BR"

git push origin "$LOCAL_BR":"$REPO_MERG_BR"
