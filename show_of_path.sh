#!/bin/bash
# set -ex
#
# find a OF bootpath on Apple PowerMacintosh Newworld machines
# Copyright (C) 2000, 2004 Olaf Hering olh@suse.de
#
# When booting via BootX then all symlinks are gone ...
# The MacOS removes them and BenH didn't find (yet) a way to
# bring them back.
# If it looks like a hack then you don't need fielmann.de
#
# Changes
#
# 2004-01-30  sysfs was born
# 2000-08-09  use hd as alias for hda instead of ultra0
# 2000-08-04  run only on pmac new
# 2000-07-19  remove sr* and scd*, not supported yet.
# 2000-07-11  add mesh for Lombard PowerBook
# 2000-07-10  finished the scsi path names for aic and symb
# 2000-07-09  clean up /proc/scsi/scsi parsing
# 2000-07-08  clean up some variable names
# 2000-04-26  get rid of strings
# 2000-04-13  get rid of awk, no success
# 2000-03-28  fix scsi on new macs when boot via bootx
# 2000-02-21  giving up and guess it all from aliases ;-)
# 2000-02-20  finish scsi host, works only with one host for now ...
# 2000-02-01  find ide hosts
# 2000-01-30  first try with scsi hosts
#

if false; then    
#if true; then    
    function dbg_show() {
	while [ "$1" ]; do
	    echo $1 = ${!1}
	    shift
	done
    }
else
    function dbg_show() {
	:
    }
fi

myversion=2004-05-05
# if no file path is given on cmd line check for root file system
file=/

if [ "$#" -gt 0 ] ; then
    until  [ "$#" = 0 ] ; do
	case "$1" in
	    --version|-v)
		echo $myversion
		exit 0
		;;
  	    --help|-h)
		echo "show OpenFirmware device path for a file or a device node"
		echo "usage: ${0##*/} [--quiet|-q] [/]|[/boot/vmlinux]"
		exit 0
		;;
	    --quiet|-q)
		quietmode=1
		;;
	    *)
	       	file=$1
	       	break
	       	;;
	esac
	shift
    done
fi

# check if we run on a NewWorld PowerMacintosh
if [ -f /proc/device-tree/openprom/model ] ; then
    while read openfirmware ofversion; do
	case "$openfirmware" in
	  iMac,1|OpenFirmware)	MACHINE="pmac_new" ;;
	  Open)			MACHINE="pmac_old" ;;
	esac
    done < <(cat /proc/device-tree/openprom/model;echo)
fi

if [ "$MACHINE" = "pmac_old" ]; then
    echo 1>&2 "ERROR: This machine is an Oldworld, no need for firmware pathnames"
    exit 1
fi

if [ -b $file ] ; then
    read i i i i file_major file_minor i < <(ls -l "$file")
    file_major="${file_major%%,*}"
    file_minor="${file_minor##*,}"
    file=/
else
    mystat="`type -p stat`"
    if [ -z "$mystat" -o ! -x "$mystat" ] ; then
	echo 1>&2 "ERROR: GNU stat required"
	exit 1
    fi

    file_majorminor=$($mystat --format="%d" "$file")
    file_major="$[file_majorminor >> 8]"
    file_minor="$[file_majorminor & 255]"
fi
file_majorminor=$file_major:$file_minor
dbg_show file_majorminor

file_sysfs_path=
# assert that /sys is mounted, else try to mount, on fail complain
if test -d /sys/block || mount -t sysfs sysfs /sys; then
    for i in $(find /sys/block -name dev); do
	: looking at $i
	if [ "$(< $i)" = "$file_majorminor" ] ; then file_sysfs_path=$i ; break ; fi
    done
else
    echo 1>&2 "ERROR: sysfs not mounted on /sys and attempt to mount failed"
    echo 1>&2 may be no kernel 2.6.x?
    exit 1
fi

if [ -z "$file_sysfs_path" ] ; then
    [ "$quietmode" ] || echo 1>&2 "ERROR: can not find major:minor $file_majorminor for $file"
    exit 1
fi

dbg_show file_sysfs_path

file_sysfs_dir="${file_sysfs_path%/dev}"
dbg_show file_sysfs_dir
if [ ! -L "$file_sysfs_dir/device" ] ; then
    # maybe a partition
    file_partition="${file_sysfs_dir##*[a-z]}"
    dbg_show file_partition
    file_sysfs_dir="${file_sysfs_dir%/*}"
    dbg_show file_sysfs_dir
    if [ ! -L "$file_sysfs_dir/device" ] ; then
	[ "$quietmode" ] || echo 1>&2 "ERROR: driver for sysfs path $file_sysfs_dir has no full sysfs support"
	exit 1
    fi
fi

cd "$file_sysfs_dir/device"
file_full_sysfs_path="`/bin/pwd`"
file_storage_type=
cd "$file_full_sysfs_path"
case "$file_full_sysfs_path" in
    */ide[0-9]*/[0-9]*)
      	file_storage_type=ide
      	of_disk_ide_channel="${file_full_sysfs_path##*.}"
      	cd ../..
      	if [[ "$of_disk_ide_channel" == */* ]]; then
	    of_disk_ide_channel="${of_disk_ide_channel%%/*}"
	    cd ../..
	fi
      	dbg_show of_disk_ide_channel
      	;;
    */host[0-9]*/[0-9]*:[0-9]*:[0-9]*:[0-9]*)
      	# file_storage_type=scsi !! or vscsi, will be determined later
	spec="${file_full_sysfs_path##*/host[0-9]*/}"
	read of_disk_scsi_host of_disk_scsi_chan of_disk_scsi_id of_disk_scsi_lun <<< ${spec//:/ }
	dbg_show of_disk_scsi_host of_disk_scsi_chan of_disk_scsi_id of_disk_scsi_lun
	cd ../..
	;;
esac

if [ -f devspec ] ; then
    read file_of_hw_devtype < devspec
    file_of_hw_devtype=/proc/device-tree${file_of_hw_devtype}
    dbg_show file_of_hw_devtype
    if ! [ -f ${file_of_hw_devtype}/device_type ]; then
	# check for scsi@$of_disk_scsi_chan/device_type else bail out ..
	file_of_hw_devtype="${file_of_hw_devtype}/scsi@${of_disk_scsi_chan}"
	dbg_show file_of_hw_devtype
    fi
    if [ -f ${file_of_hw_devtype}/device_type ] ; then
	case "$(< ${file_of_hw_devtype}/device_type)" in
	    k2-sata-root)
		: found k2-sata-root, guessing channel
		counter=0
		for i in host[0-9]*; do
		    : working on virtual scsi host $i
		    case "$file_full_sysfs_path" in
		        */$i/*)
			    : found $i $counter
			    break
			    ;;
		        *) ;;
		    esac
		    (( counter++ ))
		done
		of_device_path=`grep -l block ${file_of_hw_devtype}/*@$counter/*/device_type`
		of_device_path=${of_device_path%/device_type}
		of_device_path=${of_device_path##/proc/device-tree}
		file_storage_type=sata
		;;
	    scsi*)
		file_storage_type=scsi
		;;
	    ide|ata)
		# TODO
		# check for right file-storage_type == ide ??
		;;
	    pci-ide|pci-ata)
		# TODO
		# check for right file-storage_type == ide ??
		;;
	    vscsi)
		file_storage_type=vscsi
		;;
	    *)
	        echo 1>&2 "ERROR: Unknown device type $(< ${file_of_hw_devtype}/device_type)"
		exit 1
	esac
    else
	echo 1>&2 "ERROR: no device_type found in ${file_of_hw_devtype}"
	exit 1
    fi

    case "$file_storage_type" in
        ide)
	    file_of_hw_path="${file_of_hw_devtype##/proc/device-tree}/disk@$of_disk_ide_channel"
	    ;;
        scsi)
	    file_of_hw_path=$(printf "%s/sd@%x,%x"  "${file_of_hw_devtype##/proc/device-tree}" $of_disk_scsi_id $of_disk_scsi_lun)
	    ;;
        sata)
	    file_of_hw_path=$of_device_path
	    ;;
        vscsi)
	    (( of_disk_vscsi_nr = ( (2 << 14) | (of_disk_scsi_chan<<5) |  (of_disk_scsi_id<<8) |  of_disk_scsi_lun ) <<48 ));
	    if [ -d ${file_of_hw_devtype}/disk ]; then
		of_disk_vscsi_dir=disk
	    elif [ -d ${file_of_hw_devtype}/sd ]; then
		of_disk_vscsi_dir=sd
	    else
		echo >&2 "ERROR: Could not find a known hard disk directory under '${file_of_hw_devtype}'"
		exit 1
	    fi	
	    file_of_hw_path=$(printf "%s/%s@%lx"  "${file_of_hw_devtype##/proc/device-tree}" $of_disk_vscsi_dir $of_disk_vscsi_nr)
	    ;;
    esac
else # no 'devspec' found
    echo >&2 "WARNING: No devspec file found for $file_full_sysfs_path"

	dbg_show file_full_sysfs_path
	# find the path via the device-tree
	dev_vendor="$(< vendor)"
	dev_device="$(< device)"
	dev_subsystem_vendor="$(< subsystem_vendor)"
	dev_subsystem_device="$(< subsystem_device)"
	for i in `find /proc/device-tree -name vendor-id`
	do
		: looking at $i
		dev_of_pci_id=
		while read a vendor_id
		do
			dev_of_pci_id="0x$vendor_id"
			break
		done  < <(od --read-bytes=8 --width=8 -t x4 $i)
		: vendor-id $dev_of_pci_id
		dev_of_pci_id=$(($dev_of_pci_id))
		dev_vendor=$(($dev_vendor))
		if [ "$dev_of_pci_id" != "$dev_vendor" ] ; then continue ; fi
		if [ ! -f "${i%/*}/device-id" ] ; then continue ; fi
		while read a device_id
		do
			dev_of_pci_id="0x$device_id"
			break
		done < <(od --read-bytes=8 --width=8 -t x4 "${i%/*}/device-id")
		: device-id $dev_of_pci_id
		dev_of_pci_id=$(($dev_of_pci_id))
		dev_device=$(($dev_device))
		if [ "$dev_of_pci_id" != "$dev_device" ] ; then continue ; fi
		if [ -f "${i%/*}/subsystem-vendor-id" ] ; then
			while read a sub_vendor_id
			do
				dev_of_pci_id="0x$sub_vendor_id"
				break
			done < <(od --read-bytes=8 --width=8 -t x4 "${i%/*}/subsystem-vendor-id")
			: sub-vendor-id $dev_of_pci_id
			dev_of_pci_id=$(($dev_of_pci_id))
			dev_subsystem_vendor=$(($dev_subsystem_vendor))
			if [ "$dev_of_pci_id" != "$dev_subsystem_vendor" ] ; then continue ; fi
			while read a sub_device_id
			do
				dev_of_pci_id="0x$sub_device_id"
				break
			done < <(od --read-bytes=8 --width=8 -t x4 "${i%/*}/subsystem-id")
			: sub-device-id $dev_of_pci_id
			dev_of_pci_id=$(($dev_of_pci_id))
			dev_subsystem_device=$(($dev_subsystem_device))
			if [ "$dev_of_pci_id" != "$dev_subsystem_device" ] ; then continue ; fi
		fi
		: found $i
		if [ -z "$of_device_list" ] ; then
			of_device_list="${i%/*}"
		else
			of_device_list="$of_device_list ${i%/*}"
		fi
	done
	dbg_show of_device_list
	case "$of_device_list" in
	    *\ *)
		: more than one controler found, fun
		for i in $of_device_list
		do
		: working on $i
			while read a addr
			do
			addr="0x$addr"
			break
			done < <(od -t x8 -j4 -N8 < $i/assigned-addresses)
		: addr $addr , pure guess ...
		grep -q ^$addr resource || continue
		: found $i
		of_device_list=$i
		break
		done
		;;
	    *)
		;;
	esac

	case "$(< $of_device_list/device_type)" in
	    k2-sata-root)
		: found k2-sata-root, guessing channel
		counter=0
		for i in host[0-9]*; do
		    : working on virtual scsi host $i
		    case "$file_full_sysfs_path" in
		        */$i/*)
			    : found $i $counter
			    break
			    ;;
			*) ;;
		    esac
		    let counter++
		done
		file_storage_type=sata
		of_device_path=`grep -l block $of_device_list/*@$counter/*/device_type`
		;;
	    *)
		of_device_path=`grep -l block $of_device_list/*/device_type`
		;;
	esac

	of_device_path=${of_device_path%/device_type}
	case "$file_storage_type" in
	    ide)
		file_of_hw_path="${of_device_path##/proc/device-tree}@$of_disk_ide_channel"
		;;
	    scsi)
		file_of_hw_path=$(printf  "%s/sd@%x,%x"  "${of_device_path##/proc/device-tree}" $of_disk_scsi_id $of_disk_scsi_lun)
		;;
	    sata)
		file_of_hw_path="${of_device_path##/proc/device-tree}"
		;;
	esac
	# no "devspec" available
fi

#
# done
#

# print the resulting open firmware path
if [ "$file" != "/" ] ; then
    echo ${file_of_hw_path}${file_partition:+:$file_partition},$file
else
    echo ${file_of_hw_path}${file_partition:+:$file_partition}
fi



#
# Local variables:
#     mode: ksh
#     mode: font-lock
#     mode: auto-fill
#     ksh-indent: 4
#     ksh-multiline-offset: 2
#     ksh-if-re: "\\s *\\b\\(if\\)\\b[^=]"
#     fill-column: 78
# End:
#

