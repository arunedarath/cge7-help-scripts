if [ -z "$1" ] || [ -z "$2" ] ; then
	echo "Pass the patch list file as arg1 and the directory containing patches as arg2"
	exit 1
else
	list="$1"
	if [ ! -f "$list" ] ; then
		echo "Patch list file is not found"
		exit
	fi

	patch_dir="$2"
	if [ ! -d "$patch_dir" ] ; then
		echo "Patch directory $patch_dir is not there"
		exit
	fi
fi

tmp_dir="/tmp/check_the_cherry_pick_tmp/"
filter_patch1="$tmp_dir/f1"
filter_patch2="$tmp_dir/f2"

for i in `cat $list`
do
	file="$patch_dir"/""$i""
	if [ ! -f "$file" ] ; then
		echo "patch $i is not found in $patch_dir"
	fi

	cid_l=$(cat $file | grep -m 1 "^ChangeID:")

	git_commit_id=$(echo $cid_l | cut -d' ' -f2)

	patch=$(git format-patch -1 $git_commit_id -o $tmp_dir)

	if [ -f "$patch" ] ; then
		filterdiff $file > $filter_patch1
		filterdiff $patch > $filter_patch2

		diff -q $filter_patch1 $filter_patch2 > /dev/null

		if [ $? -eq 1 ] ; then
			echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
			echo " ---> patch differ  $file"
			change=$(diff -ru $filter_patch1 $filter_patch2 | egrep "^\+|^\-" | egrep -v "\-\-\-|^\+\+\+")

			j=0
			new_change=""
			while read line
			do
				if [ $j -eq 0 ] ; then
					j=1
					first_line="$line"
				else
					j=0
					second_line="$line"
					f_1=$(echo $first_line | awk -F" @@ " '{print $2}')
					f_2=$(echo $second_line | awk -F" @@ " '{print $2}')
					if [ -z "$f_1" ] || [ -z "$f_2" ] ; then
						# Now eliminate lines like the below ones
						# -@@ -52,7 +52,7 @@
						# +@@ -50,7 +50,7 @@

						f_1=$(echo $first_line | awk -F"@@" '{print $2}')
						f_2=$(echo $second_line | awk -F"@@" '{print $2}')

						if [ -z "$f_1" ] || [ -z "$f_2" ] ; then
							new_change+=$(echo $first_line)
							new_change+=$(echo $second_line)
						fi
					elif [ "$f_1" != "$f_2" ] ; then
						new_change+=$(echo "$first_line")
						new_change+=$(echo "$second_line")
					fi
				fi
			done <<< "$change"

			if [ -n "$new_change" ] ; then
				echo "There seems to be some mismatches: please check the changes thoroughly"
			fi
		fi
	fi
done
