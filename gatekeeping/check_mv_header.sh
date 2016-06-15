if [ -z "$1" ] ; then
	echo "please pass the patch as argument 1"
	exit 1
else
	patch=$1
	if [ ! -f "$patch" ] ; then
		echo "$patch is not a file"
		exit 1
	fi
fi


#Source: http://git.kernel.org
#MR: 123456
#Type: Integration
#Disposition: Backport from kernel.org v3.16-rc1
#ChangeID: 2d87bbd634b0fe5aa2285fd2a095867158fb2cc3
#Description:

source_str="Source: http://git.kernel.org"
mr_str="MR: [0-9].*[0-9]"
type_str="Type: Integration"
disp_str_1="Disposition: Backport from kernel.org "
desc_str="Description:"

check_line()
{
	line_no="$1"
	line=$(echo "$extract_h" | sed -n "$line_no","$line_no"p)

	if [ "$line_no" == "1" ] ; then
		if [ "$line" != "$source_str" ] ; then
			echo "!!!!!!!!!!! source line mismatch in $patch"
		fi
	elif [ "$line_no" == "2" ] ; then
		rc=$(echo "$line" | grep -c "$mr_str")
		if [ "$rc" -eq 0 ] ; then
			echo "!!!!!!!!!!! bug line number mismatch in $patch"
		fi
	elif [ "$line_no" == "3" ] ; then
		if [ "$line" != "$type_str" ] ; then
			echo "!!!!!!!!!!! type line mismatch in $patch"
		fi
	elif [ "$line_no" == "4" ] ; then
		#save the disposition string it will be checked in line no 5"
		disp_str_saved="$line"
	elif [ "$line_no" == "5" ] ; then
		git_commit=$(echo $line | cut -d' ' -f2)
		git_desc_str=$(git describe --contains $git_commit)
		if [ -z "$git_desc_str" ] ; then
			echo "!!!!!!!!!!!  changeid $git_commit may be wrong in $patch"
		else
			git_desc=$(echo $git_desc_str |  cut -d~ -f1)
			disp_str="$disp_str_1""$git_desc"
			if [ "$disp_str_saved" != "$disp_str" ] ; then
				echo "!!!!!!!!!!! Disposition line mismatch in $patch"
			fi
		fi
	elif [ "$line_no" == "6" ] ; then
		if [ "$line" != "$desc_str" ] ; then
			echo "!!!!!!!!!!! no Description in $patch"
		fi
	fi
}

check_mv_header()
{
	extract_h=$(cat $1 | sed -n 1,20p | sed -n '/Source:/,/Description:/p')
	for i in 1 2 3 4 5 6
	do
		check_line "$i"
	done
}

check_mv_header $patch
