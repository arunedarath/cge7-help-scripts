#!/bin/bash
usage()
{
	echo "boot_image.sh -p <project dir> -k <kernel file>  -d <dtb file> -a <append name> -v"
	echo "-v option is to add git version to the kernel or dtb name"
}

TFTP_DIR="/tftpboot/"
PROJECT_DIR=

while getopts  "a:p:k:d:hv" OPTION
do
	case $OPTION in
	h)
		usage
		exit 1
		;;
	p)
		PROJECT_DIR=$OPTARG
		TFTP_DIR+=$PROJECT_DIR

		res=$(echo $PROJECT_DIR | grep -c '/$')
		if [ $res -eq 0 ] ; then
			TFTP_DIR+="/"
		fi

		if [ ! -d "$TFTP_DIR" ] ; then
			echo "creating the project directory $TFTP_DIR"
			mkdir -p $TFTP_DIR
		fi

		echo "copying files to $TFTP_DIR"
		;;
	k)
		if [ ! -f $OPTARG ] ; then
			echo "kernel image $OPTARG does not exist"
			exit 1
		else
			KERN_IMAGE=$OPTARG
			KERNEL_NAME=$(echo $OPTARG | rev | cut -d'/' -f1 | rev)
		fi
		;;
	d)
		if [ ! -f $OPTARG ] ; then
			echo "dtb file $OPTARG does not exist"
			exit 1
		else
			DTB_IMAGE=$OPTARG
			DTB_NAME=$(echo $OPTARG | rev | cut -d'/' -f1 | rev)
		fi
		;;
	a)
		APPEND="_""$OPTARG"
		;;
	v)
		VER="_ver_"
		VER+=$(git log --pretty=oneline HEAD -1 | cut -d' ' -f1)
		;;
	?)
		usage
		exit
		;;
	esac
done


KERN_BOOT="$TFTP_DIR""$KERNEL_NAME""$VER""$APPEND"
KLINK="$TFTP_DIR""uImage"
DTB_BOOT="$TFTP_DIR""$DTB_NAME""$VER""$APPEND"
DLINK="$TFTP_DIR""dtb"

if [ -z "$PROJECT_DIR" ] ; then
	echo "No separate project directory specified"
	echo "Copying files to $TFTP_DIR"
	PROJECT_DIR=$TFTP_DIR
fi

if [ -n "$KERN_IMAGE" ] ; then
	unlink $KLINK
	echo "Booting with kernel $KERN_IMAGE"
	cp $KERN_IMAGE $KERN_BOOT
	chmod +r $KERN_BOOT

	ln -s $KERN_BOOT $KLINK
fi

if [ -n "$DTB_IMAGE" ] ; then
	unlink $DLINK
	echo "Booting with dtb $DTB_IMAGE"
	cp $DTB_IMAGE $DTB_BOOT
	chmod +r $DTB_BOOT

	ln -s $DTB_BOOT $DLINK
fi
