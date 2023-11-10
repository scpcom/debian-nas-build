#!/bin/sh
ltspBase=./
cd ${ltspBase} ; ltspBase=`pwd`/ ; cd - > /dev/null
ltspEtc=${ltspBase}etc/

boardModel=nas540
FWGETURL="ftp://ftp.zyxel.com/NAS540/firmware/NAS540_V5.20(AATB.0)C0.zip"
FWUSEVER=newer
fanSpeed=keep

boardName=nas
cpuArch=armhf
distBrand=Debian
#distName=wheezy
#distName=jessie
#distName=stretch
#distName=buster
distName=bullseye
#distName=bookworm
distURL=http://ftp.us.debian.org/debian
secuURL=http://security.debian.org
imageName=debian-nas
mainRepo="main"
moreRepo="main contrib non-free"
notUbuntu=true

imageMdMount=false
imageOmv=false
imageOmvInit=true
imageHostname=${imageName}
imageEth0Ip=192.168.1.233
imageEth0Mask=255.255.255.0
imageEth1Ip=192.168.2.233
imageEth1Mask=255.255.255.0
imageRouter=192.168.1.1
imageDNS=192.168.1.1

installRecommends=1
installISCSITarget=0
installMailServer=1
installNFSServer=1
installNTPServer=1
installSMBServer=1
installMiscServer=1
installWifi=0
installIpmitool=0
installSmartctl=1

distBrandLower=`echo $distBrand | tr A-Z a-z`

if [ $cpuArch = amd64 -o $cpuArch = i386 ]; then
  boardName=pc
fi

distDeb=stretch
distKeyringFile=release-9.asc
distOmv=arrakis
versOmv=4
if [ ${distName} = bookworm ] ; then
  distDeb=bookworm
  distKeyringFile=release-12.asc
  distOmv=shaitan
  versOmv=7
elif [ ${distName} = bullseye ] ; then
  distDeb=bullseye
  distKeyringFile=release-11.asc
  distOmv=shaitan
  versOmv=6
elif [ ${distName} = buster ] ; then
  distDeb=buster
  distKeyringFile=release-10.asc
  distOmv=usul
  versOmv=5
elif [ ${distName} = stretch ] ; then
  distDeb=stretch
  distKeyringFile=release-9.asc
  distOmv=arrakis
  versOmv=4
elif [ ${distName} = jessie ] ; then
  distDeb=jessie
  distKeyringFile=release-8.asc
  distOmv=erasmus
  versOmv=3
elif [ ${distName} = wheezy ] ; then
  distDeb=wheezy
  distKeyringFile=release-7.asc
  distOmv=stoneburner
  versOmv=2
fi

# ---- functions ----

function admin_password() {
  echo " *** user admin ..."
  echo "password"
  chroot ${ltspBase}${cpuArch} passwd admin
  #chroot ${ltspBase}${cpuArch} smbpasswd -a admin
}

function user_password() {
  firstUser=`cat ${ltspBase}${cpuArch}/etc/passwd |grep '504:500' | cut -d ':' -f 1`
  if [ "x$firstUser" != "x" ]; then
    echo " *** user $firstUser ..."
    echo "password"
    chroot ${ltspBase}${cpuArch} passwd $firstUser
    echo "samba share password"
    chroot ${ltspBase}${cpuArch} smbpasswd -a $firstUser
  fi
}

# based on make_raspi2_image from https://bitbucket.org/ubuntu-mate/ubuntu-mate-rpi2/src and
# https://github.com/sneak/kvm-ubuntu-imagebuilder/blob/master/buildimage.sh#L211
function make_disk_image() {
    BASEDIR=${ltspBase}images
    BUILDDIR=${ltspBase}
    #LDRDIR=${R}/root/source
    LDRDIR=${ltspBase}archives
    RELEASE=${distName}
    R=${ltspBase}${cpuArch}

    # Build the image file
    DATE="$(date +%y.%j)"
    IMAGE="${3}-${RELEASE}-${DATE}-${cpuArch}.img"

    echo "Preparing images/${IMAGE} ......"

    local FS="${1}"
    local GB=${2}

    if [ "${FS}" != "ext4" ] && [ "${FS}" != 'f2fs' ]; then
        echo "ERROR! Unsupport filesystem requested. Exitting."
        exit 1
    fi

    if [ ${GB} -ne 1 ] && [ ${GB} -ne 2 ] && [ ${GB} -ne 3 ] && [ ${GB} -ne 4 ] && [ ${GB} -ne 8 ]; then
        echo "ERROR! Unsupport card image size requested. Exitting."
        exit 1
    fi

    if [ ${GB} -eq 1 ]; then
        SEEK=940
    elif [ ${GB} -eq 2 ]; then
        SEEK=1882
    elif [ ${GB} -eq 3 ]; then
        SEEK=2816
    elif [ ${GB} -eq 4 ]; then
        SEEK=3750
    elif [ ${GB} -eq 8 ]; then
        SEEK=7594
    fi

    BOOT_START_M=1
    BOOT_SIZE_LIMIT=96
    START_M=`expr ${BOOT_START_M} + ${BOOT_SIZE_LIMIT}`
    SIZE_LIMIT=`expr ${SEEK} - 1 - ${START_M}`

    BOOT_START=`expr ${BOOT_START_M} \* 2048`
    BOOT_SIZE=`expr ${BOOT_SIZE_LIMIT} \* 2048`
    START=`expr ${START_M} \* 2048`
    SIZE=`expr ${SIZE_LIMIT} \* 2048`

    START_B=`expr ${START_M} \* 1048576`

    mkdir -p ${BASEDIR}

    [ -e ${BASEDIR}/${IMAGE}.gz ] && rm ${BASEDIR}/${IMAGE}.gz

    if [ -e ${LDRDIR}/${boardName}-loader.bin ]; then
        START_B=`stat -c%s ${LDRDIR}/${boardName}-loader.bin`
        #dd if=${LDRDIR}/${boardName}-loader.bin of="${BASEDIR}/${IMAGE}" bs=1M count=1
        dd if=${LDRDIR}/${boardName}-loader.bin of="${BASEDIR}/${IMAGE}" bs=512
        dd if=/dev/zero of="${BASEDIR}/${IMAGE}" bs=1M count=0 seek=1
    else
        dd if=/dev/zero of="${BASEDIR}/${IMAGE}" bs=1M count=1
    fi
    dd if=/dev/zero of="${BASEDIR}/${IMAGE}" bs=1M count=0 seek=${SEEK}

    if [ ${cpuArch} != powerpc ] ; then
        cat <<EOM | sfdisk -f "${BASEDIR}/${IMAGE}" > /dev/null
unit: sectors

1 : start= ${BOOT_START}, size=  ${BOOT_SIZE}, Id= c, bootable
2 : start= ${START}, size=  ${SIZE}, Id=83
3 : start=        0, size=        0, Id= 0
4 : start=        0, size=        0, Id= 0
EOM

    else
        # loader.bin contains:
        #Partition Table: mac
        #Number  Start          End            Size           File system     Name      Flags
        # 1      512B           32767B         32256B                         Apple
        # 2      32768B         1033215B       1000448B       hfs             untitled  boot
        # ... create third partition:
        parted -s "${BASEDIR}/${IMAGE}" "mkpart ext4 ${START_B}B -0"
    fi

    BOOT_LOOP=/dev/null
    ROOT_LOOP=/dev/null
    if [ ${cpuArch} != powerpc ] ; then
        BOOT_LOOP="$(losetup -o ${BOOT_START_M}M --sizelimit ${BOOT_SIZE_LIMIT}M -f --show ${BASEDIR}/${IMAGE})"
        mkfs.vfat -n TC_BOOT -S 512 -s 16 -v "${BOOT_LOOP}" > /dev/null
        ROOT_LOOP="$(losetup -o ${START_M}M --sizelimit ${SIZE_LIMIT}M -f --show ${BASEDIR}/${IMAGE})"
    else
        ROOT_LOOP="$(losetup -o ${START_B} --sizelimit ${SIZE_LIMIT}M -f --show ${BASEDIR}/${IMAGE})"
    fi

    if [ "${FS}" == "ext4" ]; then
        if ! mkfs.ext4 -O ^metadata_csum -L TC_ROOT -m 0 "${ROOT_LOOP}" > /dev/null ; then
            mkfs.ext4 -L TC_ROOT -m 0 "${ROOT_LOOP}" > /dev/null
        fi
    else
        mkfs.f2fs -l TC_ROOT -o 1 "${ROOT_LOOP}" > /dev/null
    fi

    MOUNTDIR="${BUILDDIR}/mount"
    mkdir -p "${MOUNTDIR}"
    mount "${ROOT_LOOP}" "${MOUNTDIR}"
    mkdir -p "${MOUNTDIR}/boot"
    if [ ${cpuArch} != powerpc ] ; then
        mount "${BOOT_LOOP}" "${MOUNTDIR}/boot"
    fi

    echo "Creating images/${IMAGE} ......"

    rsync -a "$R/" "${MOUNTDIR}/" || true
    rsync -a --progress "$R/" "${MOUNTDIR}/"

    rm -rf ${MOUNTDIR}/tmp/* ${MOUNTDIR}/var/tmp/*
    if [ ${GB} -eq 2 ]; then
        sed -i s/'^deb-src'/'#deb-src'/g ${MOUNTDIR}/etc/apt/sources.list
        sed -i s/'^deb-src'/'#deb-src'/g ${MOUNTDIR}/etc/apt/sources.list.d/*.list || true
    fi

    if [ "${boardName}" = "generic" -o "${boardName}" = "mac" -o "${boardName}" = "pc" ]; then
        MR=${MOUNTDIR}

        BOOTID=1234-5678
        [ ${cpuArch} != powerpc ] && BOOTID=`sudo blkid ${BOOT_LOOP} | sed s/' '/'\n'/g | grep 'UUID=' | cut -d "=" -f 2 | sed s/'"'/''/g`
        ROOTID=`sudo blkid ${ROOT_LOOP} | sed s/' '/'\n'/g | grep 'UUID=' | cut -d "=" -f 2 | sed s/'"'/''/g`

        KERN="$(cd $MR/boot && ls vmlinu*-*)"
        VER="${KERN}"
        VER="${VER#vmlinux-}"
        VER="${VER#vmlinuz-}"

        if [ $cpuArch = amd64 -o $cpuArch = i386 ]; then
            OLDBOOTID=0796-056F
            OLDROOTID=19a9d539-2e70-4361-a4c2-227c68375759
            OLDKRNVER=3.19.0-15-generic

            sed -i s/${OLDBOOTID}/${BOOTID}/g $MR/boot/grub/grub.cfg
            sed -i s/${OLDROOTID}/${ROOTID}/g $MR/boot/grub/grub.cfg
            
            if [ -e $MR/${EFIDIR}/EFI/ubuntu/grub.cfg ]; then
                sed -i s/${OLDBOOTID}/${BOOTID}/g $MR/${EFIDIR}/EFI/ubuntu/grub.cfg
                sed -i s/${OLDROOTID}/${ROOTID}/g $MR/${EFIDIR}/EFI/ubuntu/grub.cfg
            fi

            #sed -i 's|/dev/sda1|UUID="${BOOTID}"|g' ${MOUNTDIR}/etc/fstab
            #sed -i 's|/dev/sda2|UUID="${ROOTID}"|g' ${MOUNTDIR}/etc/fstab

            sed -i s/${OLDKRNVER}/${VER}/g $MR/boot/grub/grub.cfg
            [ -e $MR/sbin/init-tc ] || sed -i 's| init=/sbin/init-tc||g' $MR/boot/grub/grub.cfg
            [ -e $MR/sbin/upstart ] || sed -i 's| init=/sbin/upstart||g' $MR/boot/grub/grub.cfg
        fi
    fi

    sed -i 's|/dev/sda1|LABEL="TC_BOOT"|g' ${MOUNTDIR}/etc/fstab
    sed -i 's|/dev/sda2|LABEL="TC_ROOT"|g' ${MOUNTDIR}/etc/fstab

    if [ ${cpuArch} != powerpc ] ; then
        umount "${MOUNTDIR}/boot"
        losetup -d "${BOOT_LOOP}"

        if cp -p $R/boot/vmlinuz-* "${MOUNTDIR}/boot/" ; then
          cp -p $R/boot/config-*     "${MOUNTDIR}/boot/"
          cp -p $R/boot/initrd.img-* "${MOUNTDIR}/boot/"        
          cp -p $R/boot/System.map-* "${MOUNTDIR}/boot/"
        fi
    fi

    umount "${MOUNTDIR}"
    losetup -d "${ROOT_LOOP}"

    DISK_LOOP=/dev/null
    DISK_LOOP="$(losetup -f --show ${BASEDIR}/${IMAGE})"

    gdisk ${DISK_LOOP} <<EOF
c
1
TC_BOOT
c
2
TC_ROOT
x
c
1
54cdf5da-deb1-b007-a694-32880502ef34
c
2
54cdf5da-deb1-f007-a694-32880502ef34
p
w
y
EOF

    losetup -d "${DISK_LOOP}"

    if [ $cpuArch != amd64 -a $cpuArch != i386 ]; then
        echo "Creating images/${IMAGE}.gz ......"
        gzip ${BASEDIR}/${IMAGE}
    fi
}

UpdateConfig() {
  true
}

askClientOpt() {
  EXTRAOPT=$(whiptail --title "Image Creator $version Extra Options" --cancel-button "Quit" --ok-button "Select" --checklist "What components would you like to use?" 22 80 10 \
    "aptrecommends" "Install Recommends" $installRecommends \
    "iscsitarget" "iSCSI Target" $installISCSITarget \
    "mailserver" "Mail Server" $installMailServer \
    "nfsserver" "NFS Server" $installNFSServer \
    "ntpserver" "NTP Server" $installNTPServer \
    "smbserver" "SMB Server" $installSMBServer \
    "miscserver" "Avahi/SNMP/FTP/TFTP Server" $installMiscServer \
    "wifi" "WiFi/WLAN" $installWifi \
    "ipmitool" "IPMI Tool" $installIpmitool \
    "smartctl" "S.M.A.R.T. Monitoring Tools" $installSmartctl \
    3>&1 1>&2 2>&3)
  r=$?

  if [ $r = 0 ]; then
    installRecommends=0
    UpdateConfig installRecommends $installRecommends
    installISCSITarget=0
    UpdateConfig installISCSITarget $installISCSITarget
    installMailServer=0
    UpdateConfig installMailServer $installMailServer
    installNFSServer=0
    UpdateConfig installNFSServer $installNFSServer
    installNTPServer=0
    UpdateConfig installNTPServer $installNTPServer
    installSMBServer=0
    UpdateConfig installSMBServer $installSMBServer
    installMiscServer=0
    UpdateConfig installMiscServer $installMiscServer
    installWifi=0
    UpdateConfig installWifi $installWifi
    installIpmitool=0
    UpdateConfig installIpmitool $installIpmitool
    installSmartctl=0
    UpdateConfig installSmartctl $installSmartctl

    for o in $EXTRAOPT ; do
        case ${o} in
            \"aptrecommends\")
                installRecommends=1
                UpdateConfig installRecommends $installRecommends
                echo enable $o 
                ;;
            \"iscsitarget\")
                installISCSITarget=1
                UpdateConfig installISCSITarget $installISCSITarget
                echo enable $o 
                ;;
            \"mailserver\")
                installMailServer=1
                UpdateConfig installMailServer $installMailServer
                echo enable $o 
                ;;
            \"nfsserver\")
                installNFSServer=1
                UpdateConfig installNFSServer $installNFSServer
                echo enable $o 
                ;;
            \"ntpserver\")
                installNTPServer=1
                UpdateConfig installNTPServer $installNTPServer
                echo enable $o 
                ;;
            \"smbserver\")
                installSMBServer=1
                UpdateConfig installSMBServer $installSMBServer
                echo enable $o 
                ;;
            \"miscserver\")
                installMiscServer=1
                UpdateConfig installMiscServer $installMiscServer
                echo enable $o 
                ;;
            \"wifi\")
                installWifi=1
                UpdateConfig installWifi $installWifi
                echo enable $o 
                ;;
            \"ipmitool\")
                installIpmitool=1
                UpdateConfig installIpmitool $installIpmitool
                echo enable $o 
                ;;
            \"smartctl\")
                installSmartctl=1
                UpdateConfig installSmartctl $installSmartctl
                echo enable $o 
                ;;
            *)
                echo what?
        esac
    done
  fi
}

WriteConfigFile() {
  cat <<EOFDRUBCF | tee ${ltspBase}${cpuArch}/etc/${distBrandLower}-build.conf
boardModel=${boardModel}
FWGETURL="${FWGETURL}"
FWUSEVER="${FWUSEVER}"
fanSpeed=${fanSpeed}
firstUser=${firstUser}
imageMdMount=${imageMdMount}
imageOmv=${imageOmv}
imageOmvInit=${imageOmvInit}
imageHostname=${imageHostname}
imageEth0Ip=${imageEth0Ip}
imageEth0Mask=${imageEth0Mask}
imageEth1Ip=${imageEth1Ip}
imageEth1Mask=${imageEth1Mask}
imageRouter=${imageRouter}
imageDNS=${imageDNS}
installRecommends=${installRecommends}
installISCSITarget=${installISCSITarget}
installMailServer=${installMailServer}
installNFSServer=${installNFSServer}
installNTPServer=${installNTPServer}
installSMBServer=${installSMBServer}
installMiscServer=${installMiscServer}
installWifi=${installWifi}
installIpmitool=${installIpmitool}
installSmartctl=${installSmartctl}
EOFDRUBCF

  mkdir -p ${ltspBase}etc
  cp -p ${ltspBase}${cpuArch}/etc/${distBrandLower}-build.conf ${ltspBase}etc/
}


# ---- main ----

if [ x$1 = xadminpassword ]; then
  admin_password
  exit 0
elif [ x$1 = xuserpassword ]; then
  user_password
  exit 0
elif [ x$1 = xdiskimage ]; then
  make_disk_image ext4 3 $imageName
  exit 0
fi


echo " *** install packages on build host ..."
apt-get install -y debootstrap qemu-user-static binfmt-support whiptail dosfstools rsync patch
apt-get install -y python-minimal || apt-get install -y python2-minimal

[ -e ${ltspBase}etc/${distBrandLower}-build.conf ] && . ${ltspBase}etc/${distBrandLower}-build.conf
[ -e ${ltspBase}${cpuArch}/etc/${distBrandLower}-build.conf ] && . ${ltspBase}${cpuArch}/etc/${distBrandLower}-build.conf

BMODEL=$(whiptail --default-item ${boardModel} --title "Image Creator Firmware Extraction" --cancel-button "Quit" --ok-button "Select" --menu "Which firmware would you like to download to get hardware tools?" 18 72 10 \
    "nsa310s" "Zyxel NSA310S" \
    "nsa320s" "Zyxel NSA320S" \
    "nsa325" "Zyxel NSA325" \
    "nas326" "Zyxel NAS326" \
    "nas520" "Zyxel NAS520" \
    "nas540" "Zyxel NAS540" \
    "nas542" "Zyxel NAS542" \
    "nas5xx" "Enter Download Link ->" \
    "onboot" "Get tools on first boot" \
    3>&1 1>&2 2>&3)

boardModelEOL=nsa310a

if [ "x$BMODEL" = "xold" ]; then
	BMODEL=$(whiptail --default-item ${boardModelEOL} --title "Image Creator Firmware Extraction" --cancel-button "Quit" --ok-button "Select" --menu "Which firmware would you like to use to get tools?" 18 72 10 \
	    "nsa210" "Zyxel NSA210" \
	    "nsa220p" "Zyxel NSA220Plus" \
	    "nsa221" "Zyxel NSA221" \
	    "nsa2401" "Zyxel NSA2401" \
	    "nsa310a" "Zyxel NSA310" \
	    3>&1 1>&2 2>&3)
fi

if [ "x$BMODEL" = "nas5xx" ]; then
	INIT=$FWGETURL
	FWGETURL=$(whiptail --inputbox "Enter the URL for FW download" 8 78 $INIT --title "FW URL" 3>&1 1>&2 2>&3)
fi

if [ ! -z $BMODEL ]; then
	boardModel=${BMODEL}
fi

FWOLDVER="5.11"
case ${boardModel} in
    nsa210)  FWOLDVER="4.23" ;;
    nsa220p) FWOLDVER="3.23" ;;
    nsa221)  FWOLDVER="4.41" ;;
    nsa2401) FWOLDVER="1.11" ;;
    nsa310a) FWOLDVER="4.22" ;;
    nsa310s) FWOLDVER="4.75(AALH.0)" ;;
    nsa320s) FWOLDVER="4.75(AANV.0)" ;;
    nsa325)  FWOLDVER="4.80" ;;
esac

FWNEWVER="5.21"
case ${boardModel} in
    nsa210)  FWNEWVER="4.41" ;;
    nsa220p) FWNEWVER="3.25" ;;
    nsa221)  FWNEWVER="4.41" ;;
    nsa2401) FWNEWVER="1.20" ;;
    nsa310a) FWNEWVER="4.40" ;;
    nsa310s) FWNEWVER="4.75(AALH.1)" ;;
    nsa320s) FWNEWVER="4.75(AANV.1)" ;;
    nsa325)  FWNEWVER="4.81" ;;
    nas326)  FWNEWVER="5.21" ;;
esac

if [ "${boardModel}" != "onboot" -a "${boardModel}" != "nas5xx" ]; then
  BFWUSEVER=$(whiptail --default-item ${FWUSEVER} --title "Image Creator Firmware Extraction" --cancel-button "Quit" --ok-button "Select" --menu "Which firmware version would you like to download?" 18 72 10 \
    "older" "V${FWOLDVER}" \
    "newer" "V${FWNEWVER}" \
    3>&1 1>&2 2>&3)

  if [ ! -z $BFWUSEVER ]; then
  	FWUSEVER=${BFWUSEVER}
  fi
fi



FSPEED=$(whiptail --default-item ${fanSpeed} --title "Image Creator Fan Speed" --cancel-button "Quit" --ok-button "Select" --menu "Which fan speed should be set on boot (NAS5xx only)?" 18 72 10 \
    "0x00000fa0" "600 rpm" \
    "0x00000dac" "750 rpm" \
    "0x00000bb8" "900 rpm" \
    "0x000009c4" "1000 rpm" \
    "0x000007d0" "1100 rpm" \
    "0x000005dc" "1200 rpm" \
    "0x000003e8" "1300 rpm" \
    "keep" "No change" \
    3>&1 1>&2 2>&3)

if [ ! -z $FSPEED ]; then
	fanSpeed=${FSPEED}
fi

mdMountDefault="--defaultno"
if $imageMdMount = true ]; then
  mdMountDefault=""
fi

erexitstatus=0
whiptail $mdMountDefault --title "MD mount on boot" --yesno "Autostart MD RAID and mount volumes on boot?" 8 72 || erexitstatus=$?

if [ $erexitstatus = 0 ]; then
	imageMdMount=true
else
	imageMdMount=false
fi

omvDefault="--defaultno"
if ${imageOmv} = true ]; then
  omvDefault=""
fi

erexitstatus=0
whiptail $omvDefault --title "Install openmediavault" --yesno "Would you like to include openmediavault?" 8 72 || erexitstatus=$?

if [ $erexitstatus = 0 ]; then
	imageOmv=true
else
	imageOmv=false
fi

if ${imageOmv} = true ]; then
  installRecommends=1
  installISCSITarget=1
  installMailServer=1
  installNFSServer=1
  installNTPServer=1
  installSMBServer=1
  installMiscServer=1
  installSmartctl=1

  if [ ${versOmv} -gt 3 ]; then
    installISCSITarget=0
  fi
  if [ ${versOmv} -gt 4 ]; then
    installNTPServer=0
  fi

  omviDefault="--defaultno"
  if ${imageOmvInit} = true ]; then
  omviDefault=""
  fi

  erexitstatus=0
  whiptail $omviDefault --title "Init openmediavault on boot" --yesno "Autostart omv-initsystem on first boot?" 8 72 || erexitstatus=$?

  if [ $erexitstatus = 0 ]; then
  	imageOmvInit=true
  else
  	imageOmvInit=false
  fi

else
  askClientOpt
fi



if [ ! -e ${ltspBase}${cpuArch}/tmp/debootstrap.done ]; then
  echo " *** debootstrap ..."

  mkdir -p ${ltspBase}etc
  distKeyringUrl=https://ftp-master.debian.org/keys/${distKeyringFile}
  #wget -O ${ltspEtc}${distKeyringFile} ${distKeyringUrl}
  wget ${distKeyringUrl} -qO- | gpg --import --no-default-keyring --keyring ${ltspEtc}${distKeyringFile}.gpg

  #--keyring=${ltspEtc}${distKeyringFile}
  debootstrap --arch ${cpuArch} --foreign --variant=minbase --include=locales --keyring=${ltspEtc}${distKeyringFile}.gpg ${distName} ${ltspBase}${cpuArch} ${distURL}

  cp -p /usr/bin/qemu-arm-static ${ltspBase}${cpuArch}/usr/bin/

  echo " *** debootstrap second stage ..."

  chroot ${ltspBase}${cpuArch} /debootstrap/debootstrap --second-stage || true

  touch ${ltspBase}${cpuArch}/tmp/debootstrap.done
else
  bash ${ltspBase}drushut-${cpuArch}.sh || true
  bash ${ltspBase}drushut-${cpuArch}.sh || true
fi

if [ -e ${ltspBase}${cpuArch}/etc/resolv.conf ]; then
  [ ! -e ${ltspBase}${cpuArch}/etc/resolv.conf-resolvconf ] && chroot ${ltspBase}${cpuArch} cp -pP /etc/resolv.conf /etc/resolv.conf-resolvconf
fi

if [ -e ${ltspBase}${cpuArch}/etc/resolv.conf-resolvconf ]; then
  chroot ${ltspBase}${cpuArch} cp -pP /etc/resolv.conf-resolvconf /etc/resolv.conf
fi

echo " *** add repositories ..."

cat <<EOFASLR | tee ${ltspBase}${cpuArch}/etc/apt/sources.list
deb ${distURL}/ ${distName} ${moreRepo}
#deb-src ${distURL}/ ${distName} ${moreRepo}
EOFASLR

cat <<EOFASLU | tee -a ${ltspBase}${cpuArch}/etc/apt/sources.list
deb ${distURL}/ ${distName}-updates ${moreRepo}
#deb-src ${distURL}/ ${distName}-updates ${moreRepo}
EOFASLU

if [ $distName = bullseye -o $distName = bookworm ]; then
cat <<EOFASLS | tee -a ${ltspBase}${cpuArch}/etc/apt/sources.list
deb ${secuURL}/ ${distName}-security main contrib non-free
#deb-src ${secuURL}/ ${distName}-security main contrib non-free
EOFASLS
else
cat <<EOFASLS | tee -a ${ltspBase}${cpuArch}/etc/apt/sources.list
deb ${secuURL}/ ${distName}/updates main contrib non-free
#deb-src ${secuURL}/ ${distName}/updates main contrib non-free
EOFASLS
fi

touch ${ltspBase}${cpuArch}/tmp/repositories.done


echo " *** language settings ..."

defaultLocale=`echo ${LANG} | sed s/'utf8'/'UTF-8'/g`
defaultLocaleRegion=`echo ${defaultLocale} | cut -d "." -f 1`
defaultLocaleShort=`echo ${defaultLocale} | cut -d "_" -f 1`
defaultLocaleCharMap=`echo ${defaultLocale} | cut -d "." -f 2`
kbLayoutcode=`cat /etc/default/keyboard | grep XKBLAYOUT | cut -d "=" -f 2 | cut -d '"' -f 2`

tzArea=`cat /etc/timezone | cut -d "/" -f 1`
tzZone=`cat /etc/timezone | cut -d "/" -f 2`

kbLayoutcode=`cat /etc/default/keyboard | grep XKBLAYOUT | cut -d "=" -f 2 | cut -d '"' -f 2`
kbModelcode=`cat /etc/default/keyboard | grep XKBMODEL | cut -d "=" -f 2 | cut -d '"' -f 2`
kbVariantcode=`cat /etc/default/keyboard | grep XKBVARIANT | cut -d "=" -f 2 | cut -d '"' -f 2`
kbOptionscode=`cat /etc/default/keyboard | grep XKBOPTIONS | cut -d "=" -f 2 | cut -d '"' -f 2`

kbXkbkeymap="${kbLayoutcode}"
if [ -n $kbVariantcode ]; then
  kbXkbkeymap="${kbLayoutcode}(${kbVariantcode})"
fi

if [ ! -e ${ltspBase}${cpuArch}/tmp/language.done ]; then
  if $notUbuntu ; then
    echo 'LANG='${defaultLocale} | tee ${ltspBase}${cpuArch}/etc/default/locale
    [ ! -e ${ltspBase}${cpuArch}/etc/locale.gen-backup ] && cp -p ${ltspBase}${cpuArch}/etc/locale.gen ${ltspBase}${cpuArch}/etc/locale.gen-backup
    echo ${defaultLocale}' '${defaultLocaleCharMap} | tee ${ltspBase}${cpuArch}/etc/locale.gen
  else
    chroot ${ltspBase}${cpuArch} apt-get install -y language-pack-en-base
    chroot ${ltspBase}${cpuArch} apt-get install -y language-pack-${defaultLocaleShort}-base
    #sed -i s/'LANG=C'/'LANG=de_DE'/g /etc/default/locale
    echo 'LANG="'${defaultLocale}'"' | tee ${ltspBase}${cpuArch}/etc/default/locale
  fi

  chroot ${ltspBase}${cpuArch} apt-get update
  chroot ${ltspBase}${cpuArch} locale-gen ${defaultLocaleRegion}
  chroot ${ltspBase}${cpuArch} dpkg-reconfigure -f noninteractive locales

  if $notUbuntu ; then
    #cat ${ltspBase}${cpuArch}/etc/locale.gen | grep '# '${defaultLocaleShort} | sed s/'# '${defaultLocaleShort}/${defaultLocaleShort}/g | tee ${ltspBase}${cpuArch}/etc/locale.gen
    cat ${ltspBase}${cpuArch}/etc/locale.gen-backup | sed s/'# '${defaultLocaleShort}/${defaultLocaleShort}/g | grep ^${defaultLocaleShort} | tee ${ltspBase}${cpuArch}/etc/locale.gen
    chroot ${ltspBase}${cpuArch} debconf-set-selections <<EOFDRUDCSLO
locales locales/default_environment_locale select ${defaultLocale}
EOFDRUDCSLO

    chroot ${ltspBase}${cpuArch} dpkg-reconfigure -f noninteractive locales
  fi

  grep -q 'LANGUAGE='    ${ltspBase}${cpuArch}/etc/default/locale || echo 'LANGUAGE="'${defaultLocaleShort}'"' | tee -a ${ltspBase}${cpuArch}/etc/default/locale
  grep -q 'LC_MESSAGES=' ${ltspBase}${cpuArch}/etc/default/locale || echo 'LC_MESSAGES="'${defaultLocale}'"'   | tee -a ${ltspBase}${cpuArch}/etc/default/locale

  chroot ${ltspBase}${cpuArch} apt-get update

  echo "${tzArea}/${tzZone}" | tee ${ltspBase}${cpuArch}/etc/timezone

  [ -e ${ltspBase}${cpuArch}/usr/share/zoneinfo/${tzArea}/${tzZone} ] && ln -sf /usr/share/zoneinfo/${tzArea}/${tzZone} ${ltspBase}${cpuArch}/etc/localtime

  mkdir -p ${ltspBase}${cpuArch}/root/board-debs

  cat <<EOFDRUDCSI | tee ${ltspBase}${cpuArch}/root/board-debs/debconf-selections.txt
console-setup	console-setup/codesetcode	string	Lat15
console-setup	console-setup/fontsize-fb47	select	16
console-setup	console-setup/codeset47	select	# Latin1 and Latin5 - western Europe and Turkic languages
console-setup	console-setup/fontsize	string	16
console-setup	console-setup/store_defaults_in_debconf_db	boolean	true
console-setup	console-setup/charmap47	select	${defaultLocaleCharMap}
console-setup	console-setup/fontface47	select	VGA
console-setup	console-setup/fontsize-text47	select	16
console-setup	console-setup/ask_detect	boolean	false
console-setup	console-setup/charmap	select	${defaultLocaleCharMap}
console-setup	console-setup/codeset	select	# Latin1 and Latin5 - western Europe and Turkic languages
console-setup	console-setup/compose	select	No compose key
console-setup	console-setup/detected	note	
console-setup	console-setup/fontface	select	VGA
console-setup	console-setup/fontsize-fb	select	16
console-setup	console-setup/fontsize-text	select	16
console-setup	console-setup/layoutcode	string	${kbLayoutcode}
console-setup	console-setup/modelcode	string	${kbModelcode}
console-setup	console-setup/optionscode	string	${kbOptionscode}
console-setup	console-setup/switch	select	No temporary switch
console-setup	console-setup/toggle	select	No toggling
console-setup	console-setup/ttys	string	/dev/tty[1-6]
console-setup	console-setup/unsupported_config_layout	boolean	true
console-setup	console-setup/unsupported_config_options	boolean	true
console-setup	console-setup/unsupported_layout	boolean	true
console-setup	console-setup/unsupported_options	boolean	true
console-setup	console-setup/variantcode	string	${kbVariantcode}
keyboard-configuration	keyboard-configuration/modelcode	string	${kbModelcode}
keyboard-configuration	keyboard-configuration/ctrl_alt_bksp	boolean	false
keyboard-configuration	keyboard-configuration/optionscode	string	${kbOptionscode}
keyboard-configuration	keyboard-configuration/compose	select	No compose key
keyboard-configuration	keyboard-configuration/layoutcode	string	${kbLayoutcode}
keyboard-configuration	keyboard-configuration/toggle	select	No toggling
keyboard-configuration	keyboard-configuration/store_defaults_in_debconf_db	boolean	true
keyboard-configuration	console-setup/ask_detect	boolean	false
keyboard-configuration	keyboard-configuration/unsupported_config_layout	boolean	true
keyboard-configuration	keyboard-configuration/xkb-keymap	select	${kbXkbkeymap}
keyboard-configuration	keyboard-configuration/variantcode	string	${kbVariantcode}
keyboard-configuration	keyboard-configuration/unsupported_layout	boolean	true
keyboard-configuration	keyboard-configuration/switch	select	No temporary switch
keyboard-configuration	keyboard-configuration/unsupported_options	boolean	true
keyboard-configuration	keyboard-configuration/unsupported_config_options	boolean	true
tzdata	tzdata/Areas	select	${tzArea}
tzdata	tzdata/Zones/${tzArea}	select	${tzZone}
EOFDRUDCSI

  touch ${ltspBase}${cpuArch}/tmp/language.done
fi


cat <<EOFDRUDCSJN | tee ${ltspBase}${cpuArch}/root/board-debs/debconf-selections-nbd.txt
jackd2	jackd/tweak_rt_limits	boolean	false
nbd-client	nbd-client/killall	boolean	false
nbd-client	nbd-client/host	string	
nbd-client	nbd-client/port	string	
nbd-client	nbd-client/device	string	
nbd-client	nbd-client/type	select	raw
nbd-client	nbd-client/number	string	0
nbd-client	nbd-client/extra	string	
EOFDRUDCSJN

cat <<EOFDRUDCSD | tee ${ltspBase}${cpuArch}/root/board-debs/debconf-selections-dash.txt
dash    dash/sh boolean false
EOFDRUDCSD


echo " *** install packages ..."

WriteConfigFile

chroot ${ltspBase}${cpuArch} mount -t proc /proc /proc

mkdir -p ${ltspBase}${cpuArch}/root/bin
cp ${ltspBase}dru-nas.txt ${ltspBase}${cpuArch}/root/bin/dru-nas.sh
chmod ugo+rx ${ltspBase}${cpuArch}/root/bin/dru-nas.sh
cp ${ltspBase}dru-omv.txt ${ltspBase}${cpuArch}/root/bin/dru-omv.sh
chmod ugo+rx ${ltspBase}${cpuArch}/root/bin/dru-omv.sh
cp ${ltspBase}dru-usr.txt ${ltspBase}${cpuArch}/root/bin/dru-usr.sh
chmod ugo+rx ${ltspBase}${cpuArch}/root/bin/dru-usr.sh
#cp ${ltspBase}dru-post.txt ${ltspBase}${cpuArch}/root/bin/dru-post.sh
#chmod ugo+rx ${ltspBase}${cpuArch}/root/bin/dru-post.sh

mkdir -p ${ltspBase}${cpuArch}/root/source
cp -p ${ltspBase}archives/openmediavault-init-scripts.tar.gz ${ltspBase}${cpuArch}/root/source/

chroot ${ltspBase}${cpuArch} bash -e /root/bin/dru-nas.sh

if [ ${imageOmv} = true ]; then
	chroot ${ltspBase}${cpuArch} bash -e /root/bin/dru-omv.sh
fi


linuxImageSuffix="-generic"

if [ $cpuArch = "i386" ]; then
	linuxImageSuffix="-686-pae"
elif [ $cpuArch = "amd64" ]; then
	linuxImageSuffix="-amd64"
elif [ $cpuArch = "armhf" ]; then
	linuxImageSuffix="-armmp"
fi

mkdir -p ${ltspBase}${cpuArch}/root/board-debs

cat <<EOFDRULININST | tee ${ltspBase}${cpuArch}/root/board-debs/drulininst.sh > /dev/null
#!/bin/bash

apt-get install -y linux-image${linuxImageSuffix}

if [ $cpuArch = amd64 -o $cpuArch = i386 ]; then
  DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install -y grub-pc

  update-grub-gfxpayload || ${notUbuntu}

  mkdir -p /boot/grub/fonts
  mkdir -p /boot/grub/i386-pc
  mkdir -p /boot/grub/locale
  cp -p /usr/lib/grub/i386-pc/*.lst /boot/grub/i386-pc/
  cp -p /usr/lib/grub/i386-pc/*.mod /boot/grub/i386-pc/
  cp -p /usr/lib/grub/i386-pc/*.o   /boot/grub/i386-pc/
  cp -p /usr/lib/grub/i386-pc/boot.img /boot/grub/i386-pc/
  #core.img?
  cp -p /usr/share/grub/unicode.pf2 /boot/grub/fonts/
  cp -p /usr/share/grub/unicode.pf2 /boot/grub/
  cp -p /usr/share/locale-langpack/${defaultLocaleShort}/LC_MESSAGES/grub.mo /boot/grub/locale/${defaultLocaleShort}.mo || ${notUbuntu}

  apt-get install -y memtest86+
  
  [ -e /usr/share/grub/default/grub ] && cp -p /usr/share/grub/default/grub /etc/default/grub
#  sed -i s/'GRUB_HIDDEN_TIMEOUT=0'/'#GRUB_HIDDEN_TIMEOUT=0'/g /etc/default/grub

  if grep GRUB_RECORDFAIL_TIMEOUT /etc/default/grub > /dev/null ; then
    sed -i 's|GRUB_RECORDFAIL_TIMEOUT=.*|GRUB_RECORDFAIL_TIMEOUT=10|g' /etc/default/grub
  else
    echo "GRUB_RECORDFAIL_TIMEOUT=10" | tee -a /etc/default/grub > /dev/null
  fi
fi

touch /tmp/\`basename \$0\`.done
echo "OK"
EOFDRULININST

chmod ugo+rx ${ltspBase}${cpuArch}/root/board-debs/drulininst.sh

if [ "${cpuArch:0:3}" != "arm" ]; then
  true
elif [ -e ${ltspBase}${cpuArch}/bin/systemctl.druic -a -e ${ltspBase}${cpuArch}/bin/systemctl.distrib ]; then
  chroot ${ltspBase}${cpuArch} rm /bin/systemctl
  chroot ${ltspBase}${cpuArch} dpkg-divert --local --rename --remove /bin/systemctl
  if [ -e ${ltspBase}${cpuArch}/bin/logger.distrib ]; then
    chroot ${ltspBase}${cpuArch} rm /bin/logger
    chroot ${ltspBase}${cpuArch} dpkg-divert --local --rename --remove /bin/logger
  fi
fi

chroot ${ltspBase}${cpuArch} systemctl enable ssh
chroot ${ltspBase}${cpuArch} systemctl disable quota || true
chroot ${ltspBase}${cpuArch} systemctl disable quotaon
chroot ${ltspBase}${cpuArch} systemctl disable systemd-quotacheck

if [ "${cpuArch:0:3}" != "arm" ]; then
  true
elif [ -e ${ltspBase}${cpuArch}/sbin/quotacheck -a ! -e ${ltspBase}${cpuArch}/sbin/quotacheck.distrib ]; then
  chroot ${ltspBase}${cpuArch} dpkg-divert --local --rename --add /sbin/quotacheck
  chroot ${ltspBase}${cpuArch} ln -s /bin/true /sbin/quotacheck
fi

if [ ${imageOmv} = true ]; then
  chroot ${ltspBase}${cpuArch} systemctl disable openmediavault-beep-down
  chroot ${ltspBase}${cpuArch} systemctl disable openmediavault-beep-up
fi

if [ "${cpuArch:0:3}" != "arm" ]; then
	chroot ${ltspBase}${cpuArch} bash -e /root/board-debs/drulininst.sh

	cd ${ltspBase}${cpuArch}
	tar xzvf ${ltspBase}archives/${boardName}-bootloader-${cpuArch}.tar.gz
	cd -
fi


for z in `ls ${ltspBase}archives/linux-bsp-*-${cpuArch}.zip` ; do
  zd=`basename ${z}`
  zd=${zd/linux-bsp-/}
  zd=${zd/-${cpuArch}.zip/}
  zs=install-bsp-boot.sh

  mkdir -p ${ltspBase}${cpuArch}/root/board-debs/${zd}

  cd ${ltspBase}${cpuArch}/root/board-debs/${zd}
  unzip -o ${z}
  if [ -e install-bsp.sh ]; then
    zs=install-bsp.sh
  fi
  cd - > /dev/null

  sed -i s/'sudo '/''/g ${ltspBase}${cpuArch}/root/board-debs/${zd}/${zs}
  chroot ${ltspBase}${cpuArch} /root/board-debs/${zd}/${zs}

  cd ${ltspBase}${cpuArch}/root/board-debs
  if [ ! -e ${zs} ]; then
    ln -s ${zd}/${zs} ${zs}
  fi
  cd - > /dev/null
done


chroot ${ltspBase}${cpuArch} bash -e /root/bin/dru-usr.sh

chroot ${ltspBase}${cpuArch} umount /proc


echo " *** configuration ..."

INIT=$imageHostname
imageHostname=$(whiptail --inputbox "Enter the hostname" 8 78 $INIT --title "Hostname" 3>&1 1>&2 2>&3)

INIT=$imageEth0Ip
imageEth0Ip=$(whiptail --inputbox "Enter the IP for eth0/egiga0 (leave empty for dhcp)" 8 78 $INIT --title "First NIC Interface IP" 3>&1 1>&2 2>&3)

if [ "x${imageEth0Ip}" != "x" -a "x${imageEth0Ip}" != "xdhcp" ]; then
  INIT=$imageEth0Mask
  imageEth0Mask=$(whiptail --inputbox "Enter the network mask for eth0/egiga0" 8 78 $INIT --title "First NIC Interface Mask" 3>&1 1>&2 2>&3)
else
  imageRouter=
  imageDNS=
fi

INIT=$imageEth1Ip
imageEth1Ip=$(whiptail --inputbox "Enter the IP for eth1/egiga1 (leave empty to skip)" 8 78 $INIT --title "Second NIC Interface IP" 3>&1 1>&2 2>&3)

if [ "x${imageEth1Ip}" != "x" -a "x${imageEth1Ip}" != "xdhcp" ]; then
  INIT=$imageEth1Mask
  imageEth1Mask=$(whiptail --inputbox "Enter the network mask for eth1/egiga1" 8 78 $INIT --title "Second NIC Interface Mask" 3>&1 1>&2 2>&3)
fi

INIT=$imageRouter
imageRouter=$(whiptail --inputbox "Enter the IP for gateway/router (leave empty to skip)" 8 78 $INIT --title "Gateway IP" 3>&1 1>&2 2>&3)

INIT=$imageDNS
imageDNS=$(whiptail --inputbox "Enter the IP for DNS/nameserver (leave empty to skip)" 8 78 $INIT --title "DNS IP" 3>&1 1>&2 2>&3)


#date "+%Y-%m-%d %H:%M:%S"
date "+%Y-%m-01 00:%M:%S" | tee ${ltspBase}${cpuArch}/etc/fake-hwclock.data

cat <<EOFDRUNI | tee ${ltspBase}${cpuArch}/etc/network/interfaces-dhcp > /dev/null
# The loopback network interface
auto lo
iface lo inet loopback
EOFDRUNI
#iface default inet dhcp
#allow-hotplug wlan0
#iface wlan0 inet manual
#wpa-roam /etc/wpa_supplicant/wpa_supplicant.conf

if [ ! -e ${ltspBase}${cpuArch}/etc/network/interfaces-ifupdown ]; then
  mv ${ltspBase}${cpuArch}/etc/network/interfaces      ${ltspBase}${cpuArch}/etc/network/interfaces-ifupdown
fi
mv ${ltspBase}${cpuArch}/etc/network/interfaces-dhcp ${ltspBase}${cpuArch}/etc/network/interfaces


echo "${imageHostname}" > ${ltspBase}${cpuArch}/etc/hostname

cat <<EOFDRUHOSTS | tee ${ltspBase}${cpuArch}/etc/hosts
127.0.0.1	 localhost
::1		 localhost ip6-localhost ip6-loopback
fe00::0		 ip6-localnet
ff00::0		 ip6-mcastprefix
ff02::1		 ip6-allnodes
ff02::2		 ip6-allrouters
127.0.1.1	 ${imageHostname}
EOFDRUHOSTS


if [ "x${imageEth0Ip}" != "x" -a "x${imageEth0Ip}" != "xdhcp" ]; then
cat <<EOFDRUE0SNI | tee -a ${ltspBase}${cpuArch}/etc/network/interfaces > /dev/null

# eth0 network interface
auto eth0
allow-hotplug eth0
iface eth0 inet static
    address ${imageEth0Ip}
    netmask ${imageEth0Mask}
EOFDRUE0SNI

if [ "x${imageRouter}" != "x" ]; then
cat <<EOFDRUE0SNJ | tee -a ${ltspBase}${cpuArch}/etc/network/interfaces > /dev/null
    gateway ${imageRouter}
EOFDRUE0SNJ
fi

if [ "x${imageDNS}" != "x" ]; then
cat <<EOFDRUE0SNK | tee -a ${ltspBase}${cpuArch}/etc/network/interfaces > /dev/null
    dns-nameservers ${imageDNS}
EOFDRUE0SNK
fi

cat <<EOFDRUE0SNL | tee -a ${ltspBase}${cpuArch}/etc/network/interfaces > /dev/null
iface eth0 inet6 manual
    pre-down ip -6 addr flush dev \$IFACE
EOFDRUE0SNL

else
cat <<EOFDRUE0SNI | tee -a ${ltspBase}${cpuArch}/etc/network/interfaces > /dev/null

# eth0 network interface
auto eth0
allow-hotplug eth0
iface eth0 inet dhcp
iface eth0 inet6 manual
    pre-down ip -6 addr flush dev \$IFACE
EOFDRUE0SNI
fi


if [ "x${imageEth1Ip}" != "x" -a "x${imageEth1Ip}" != "xdhcp" ]; then
cat <<EOFDRUE1SNI | tee -a ${ltspBase}${cpuArch}/etc/network/interfaces > /dev/null

# eth1 network interface
auto eth1
allow-hotplug eth1
iface eth1 inet static
    address ${imageEth1Ip}
    netmask ${imageEth1Mask}
iface eth1 inet6 manual
    pre-down ip -6 addr flush dev \$IFACE
EOFDRUE1SNI

elif [ "x${imageEth1Ip}" = "xdhcp" ]; then
cat <<EOFDRUE1SNI | tee -a ${ltspBase}${cpuArch}/etc/network/interfaces > /dev/null

# eth1 network interface
auto eth1
allow-hotplug eth1
iface eth1 inet dhcp
iface eth1 inet6 manual
    pre-down ip -6 addr flush dev \$IFACE
EOFDRUE1SNI
fi


if [ "x${imageDNS}" != "x" ]; then
  rm -f ${ltspBase}${cpuArch}/etc/resolv.conf

  cat <<EOFDRURSLVC | tee ${ltspBase}${cpuArch}/etc/resolv.conf
nameserver ${imageDNS}
EOFDRURSLVC

  if [ -e ${ltspBase}${cpuArch}/run/resolvconf/interface ]; then
    cp -p ${ltspBase}${cpuArch}/etc/resolv.conf ${ltspBase}${cpuArch}/run/resolvconf/interface/original.resolvconf
  fi
fi


if ! grep -E '^precedence ::ffff:0:0/96  100' ${ltspBase}${cpuArch}/etc/gai.conf > /dev/null ; then
  echo "precedence ::ffff:0:0/96  100" | tee -a ${ltspBase}${cpuArch}/etc/gai.conf
fi

if ! grep -E '^net.ipv6.conf.all.disable_ipv6' ${ltspBase}${cpuArch}/etc/sysctl.conf > /dev/null ; then
  cat <<EOFDRUSC | tee -a ${ltspBase}${cpuArch}/etc/sysctl.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOFDRUSC
fi


mkdir -p ${ltspBase}${cpuArch}/etc/tmpfiles.d

cat <<EOFDRUTFD | tee ${ltspBase}${cpuArch}/etc/tmpfiles.d/${distBrandLower}.conf
#Type Path        Mode UID  GID  Age Argument
    d    /var/log/apt      0755 root   root - -
    d    /var/log/dist-upgrade   0755 root   root - -
    d    /var/log/fsck     0755 root   root - -
    d    /var/log/lightdm  0755 root   root - -
    d    /var/log/samba    0750 root   adm  - -
    d    /var/log/upstart  0755 root   root - -
    d    /var/log/apache2       0750 root   adm  - -
    d    /var/log/chkrootkit    0755 root   root - -
    d    /var/log/cups          0755 root   root - -
    d    /var/log/freeipmi      0755 root   root - -
    d    /var/log/fsck          0755 root   root - -
    d    /var/log/ipmiconsole   0755 root   root - -
    d    /var/log/news          0755 root   root - -
    d    /var/log/iptraf        0700 root   root - -
    d    /var/log/tiger         0700 root   root - -
    d    /var/log/openmediavault 0755 root   root - -
    d    /var/log/proftpd       0755 root   root - -
EOFDRUTFD

if [ -e ${ltspBase}${cpuArch}/var/log/nginx ]; then
  cat <<EOFDRUTFD | tee -a ${ltspBase}${cpuArch}/etc/tmpfiles.d/${distBrandLower}.conf
    d    /var/log/nginx         0750 www-data adm - -
EOFDRUTFD
fi

if [ "x$installNTPServer" != "x0" ]; then
  cat <<EOFDRUTFN | tee -a ${ltspBase}${cpuArch}/etc/tmpfiles.d/${distBrandLower}.conf
    d    /var/log/ntpstats 0755 ntp    ntp  - -
EOFDRUTFN
fi


bootDisk=sda

cat <<EOFDRUFSTAB | tee ${ltspBase}${cpuArch}/etc/fstab > /dev/null
proc            /proc           proc    defaults          0       0
tmpfs           /tmp            tmpfs   defaults          0       0
EOFDRUFSTAB

if [ "${cpuArch:0:3}" != "arm" ]; then
  cat <<EOFDRUFSTAC | tee -a ${ltspBase}${cpuArch}/etc/fstab > /dev/null
tmpfs           /var/log        tmpfs   defaults          0       0
/dev/${bootDisk}1  /boot           vfat    defaults          0       2
/dev/${bootDisk}2  /               ext4    defaults,noatime,nodiratime   0       1
EOFDRUFSTAC
fi



if [ ! -e ${ltspBase}${cpuArch}/etc/rc.local ]; then
  cat <<EOFDRURCLA | tee ${ltspBase}${cpuArch}/etc/rc.local > /dev/null
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.

exit 0
EOFDRURCLA

  chmod ugo+x ${ltspBase}${cpuArch}/etc/rc.local
fi


[ ! -e ${ltspBase}${cpuArch}/etc/rc.local-debian ] && cp -p ${ltspBase}${cpuArch}/etc/rc.local ${ltspBase}${cpuArch}/etc/rc.local-debian

cp -p ${ltspBase}${cpuArch}/etc/rc.local-debian ${ltspBase}${cpuArch}/etc/rc.local
sed -i '/^exit 0/ d' ${ltspBase}${cpuArch}/etc/rc.local


if [ "${cpuArch:0:3}" = "arm" ]; then
cat <<EOFDRURCLG | tee -a ${ltspBase}${cpuArch}/etc/rc.local > /dev/null

if [ ! -e /dev/gpio ]; then
  # Create device node for gpio control
  #mknod -m 644 /dev/gpio c `cat /proc/devices  | grep gpio | awk '{print $1}'` 0
  mknod -m 644 /dev/gpio c 253 0
fi
EOFDRURCLG
fi


if [ ${fanSpeed} != keep ]; then
  echo "" | tee -a ${ltspBase}${cpuArch}/etc/rc.local
  echo "mmiotool -w 0x9045802C ${fanSpeed}" | tee -a ${ltspBase}${cpuArch}/etc/rc.local
fi


cat <<EOFDRURCLZ | tee -a ${ltspBase}${cpuArch}/etc/rc.local > /dev/null

EOFDRURCLZ


echo "exit 0" >>  ${ltspBase}${cpuArch}/etc/rc.local


if [ -e ${ltspBase}${cpuArch}/etc/avahi/avahi-daemon.conf ]; then
  sed -i s/'#disallow-other-stacks=no'/'disallow-other-stacks=yes'/g ${ltspBase}${cpuArch}/etc/avahi/avahi-daemon.conf
fi

if [ -e ${ltspBase}${cpuArch}/etc/lvm/lvm.conf ]; then
  #sed -i 's|dir = "/dev"|dir = "/dev/mapper"|g' ${ltspBase}${cpuArch}/etc/lvm/lvm.conf

  #sed -i s/'use_lvmetad = 0'/'use_lvmetad = 1'/g ${ltspBase}${cpuArch}/etc/lvm/lvm.conf

  sed -i s/'obtain_device_list_from_udev = 1'/'obtain_device_list_from_udev = 0'/g ${ltspBase}${cpuArch}/etc/lvm/lvm.conf

  #sed -i s/'sysfs_scan = 1'/'sysfs_scan = 0'/g ${ltspBase}${cpuArch}/etc/lvm/lvm.conf
fi

sed -i s/'RSYNC_ENABLE=.*'/'RSYNC_ENABLE=true'/g ${ltspBase}${cpuArch}/etc/default/rsync

[ ! -e ${ltspBase}${cpuArch}/etc/samba/smb.conf-debian ] && mv ${ltspBase}${cpuArch}/etc/samba/smb.conf ${ltspBase}${cpuArch}/etc/samba/smb.conf-debian


cp -p ${ltspBase}scripts/repack-zImage.sh ${ltspBase}${cpuArch}/usr/local/bin/
cp -p ${ltspBase}scripts/zy-fw-get-bin    ${ltspBase}${cpuArch}/usr/local/bin/
cp -p ${ltspBase}scripts/zy-fw-get-lib    ${ltspBase}${cpuArch}/usr/local/bin/

if [ $FWUSEVER = older ]; then
  case ${boardModel} in
    nsa210)  FWGETURL="ftp://ftp.zyxel.com/NSA210/firmware/old_version/NSA210_4.23(AFD.1)C0.zip" ;;
    nsa220p) FWGETURL="ftp://ftp.zyxel.com/NSA-220_Plus/firmware/NSA-220%20Plus_3.23(AFG.0)C0.zip" ;;
    nsa221)  FWGETURL="ftp://ftp.zyxel.com/NSA221/firmware/NSA221_V4.41(AFM.1)C0.zip" ;;
    nsa2401) FWGETURL="ftp://ftp.zyxel.com/NSA-2401/firmware/NSA-2401_1.11(AFF.0)C0.zip" ;;
    nsa310a) FWGETURL="ftp://ftp.zyxel.com/NSA310a/firmware/NSA310_4.22(AFK.1)C0.zip" ;;
    nsa310s) FWGETURL="ftp://ftp.zyxel.com/NSA310S/firmware/NSA310S_4.75(AALH.0)C0.zip" ;;
    nsa320s) FWGETURL="ftp://ftp.zyxel.com/NSA320S/firmware/NSA320S_V4.75(AANV.0)C0.zip" ;;
    nsa325)  FWGETURL="ftp://ftp.zyxel.com/NSA325/firmware/NSA325_V4.80(AAAJ.1)C0.zip" ;;
    nas326)  FWGETURL="ftp://ftp.zyxel.com/NAS326/firmware/NAS326_V5.11(AAZF.4)C0.zip" ;;
    nas520)  FWGETURL="ftp://ftp.zyxel.com/NAS520/firmware/NAS520_V5.11(AASZ.3)C0.zip" ;;
    nas540)  FWGETURL="ftp://ftp.zyxel.com/NAS540/firmware/NAS540_V5.11(AATB.3)C0.zip" ;;
    nas542)  FWGETURL="ftp://ftp.zyxel.com/NAS542/firmware/NAS542_V5.11(ABAG.3)C0.zip" ;;
  esac
else
  case ${boardModel} in
    nsa210)  FWGETURL="ftp://ftp.zyxel.com/NSA210/firmware/NSA210_4.41(AFD.0)C0.zip" ;;
    nsa220p) FWGETURL="ftp://ftp.zyxel.com/NSA-220_Plus/firmware/NSA-220%20Plus_3.25(AFG.0)C0.zip" ;;
    nsa221)  FWGETURL="ftp://ftp.zyxel.com/NSA221/firmware/NSA221_V4.41(AFM.1)C0.zip" ;;
    nsa2401) FWGETURL="ftp://ftp.zyxel.com/NSA-2401/firmware/NSA-2401_1.20(AFF.0)C0.zip" ;;
    nsa310a) FWGETURL="ftp://ftp.zyxel.com/NSA310a/firmware/NSA310_4.40(AFK.0)C0.zip" ;;
    nsa310s) FWGETURL="ftp://ftp.zyxel.com/NSA310S/firmware/NSA310S_V4.75(AALH.1)C0.zip" ;;
    nsa320s) FWGETURL="ftp://ftp.zyxel.com/NSA320S/firmware/NSA320S_V4.75(AANV.1)C0.zip" ;;
    nsa325)  FWGETURL="ftp://ftp.zyxel.com/NSA325/firmware/NSA325_V4.81(AAAJ.0)C0.zip" ;;
#    nas326)  FWGETURL="ftp://ftp.zyxel.com/NAS326/firmware/NAS326_V5.20(AAZF.1)C0.zip" ;;
#    nas520)  FWGETURL="ftp://ftp.zyxel.com/NAS520/firmware/NAS520_V5.20(AASZ.0)C0.zip" ;;
#    nas540)  FWGETURL="ftp://ftp.zyxel.com/NAS540/firmware/NAS540_V5.20(AATB.0)C0.zip" ;;
#    nas542)  FWGETURL="ftp://ftp.zyxel.com/NAS542/firmware/NAS542_V5.20(ABAG.1)C0.zip" ;;
    nas326)  FWGETURL="ftp://ftp.zyxel.com/NAS326/firmware/NAS326_V5.21(AAZF.0)C0.zip" ;;
    nas520)  FWGETURL="ftp://ftp.zyxel.com/NAS520/firmware/NAS520_V5.21(AASZ.0)C0.zip" ;;
    nas540)  FWGETURL="ftp://ftp.zyxel.com/NAS540/firmware/NAS540_V5.21(AATB.0)C0.zip" ;;
    nas542)  FWGETURL="ftp://ftp.zyxel.com/NAS542/firmware/NAS542_V5.21(ABAG.0)C0.zip" ;;
  esac
fi

if [ "${boardModel}" = "onboot" ]; then
  FWGETURL="file://onboot"
else
  ${ltspBase}scripts/zy-fw-extract - ${ltspBase}fw "${FWGETURL}"
fi

chroot ${ltspBase}${cpuArch} mount -t proc /proc /proc

for z in `ls ${ltspBase}kernel/gcc-*-${cpuArch}.zip` ; do
  zd=`basename ${z}`
  #zd=${zd/gcc-/}
  zd=${zd/-${cpuArch}.zip/}
  zn=`echo ${zd} | cut -d "-" -f 1-2`
  mkdir -p ${ltspBase}${cpuArch}/root/board-debs/${zd}
  cd ${ltspBase}${cpuArch}/root/board-debs/${zd}
  unzip -o ${z}
  cd - > /dev/null
  chmod ugo+rx ${ltspBase}${cpuArch}/root/board-debs/${zd}/install-${zn}.sh
  sed -i s/'sudo '/''/g ${ltspBase}${cpuArch}/root/board-debs/${zd}/install-${zn}.sh
  chroot ${ltspBase}${cpuArch} /root/board-debs/${zd}/install-${zn}.sh

  cd ${ltspBase}${cpuArch}/root/board-debs
  if [ ! -e install-gcc.sh ]; then
    ln -s ${zd}/install-${zn}.sh install-gcc.sh
  fi
  cd - > /dev/null
done

for z in `ls ${ltspBase}kernel/linux-tools-*-${cpuArch}.zip` ; do
  zd=`basename ${z}`
  zd=${zd/linux-/}
  zd=${zd/-${cpuArch}.zip/}
  mkdir -p ${ltspBase}${cpuArch}/root/board-debs/${zd}
  cd ${ltspBase}${cpuArch}/root/board-debs/${zd}
  unzip -o ${z}
  cd - > /dev/null
  sed -i s/'sudo '/''/g ${ltspBase}${cpuArch}/root/board-debs/${zd}/install-kbuild.sh
  chroot ${ltspBase}${cpuArch} /root/board-debs/${zd}/install-kbuild.sh

  cd ${ltspBase}${cpuArch}/root/board-debs
  if [ ! -e install-kbuild.sh ]; then
    ln -s ${zd}/install-kbuild.sh install-kbuild.sh
  fi
  cd - > /dev/null
done

for z in `ls ${ltspBase}kernel/linux-image-*-${cpuArch}.zip` ; do
  zd=`basename ${z}`
  zd=${zd/linux-image-/}
  zd=${zd/-${cpuArch}.zip/}
  mkdir -p ${ltspBase}${cpuArch}/root/board-debs/${zd}
  cd ${ltspBase}${cpuArch}/root/board-debs/${zd}
  unzip -o ${z}
  cd - > /dev/null
  # prefer existing bsp
  find ${ltspBase}${cpuArch}/root/board-debs/nas5xx-*/ -name linux-bsp-nas5xx_*.deb | while read k ; do
    b=`basename $k`
    if [ -e ${ltspBase}${cpuArch}/root/board-debs/${zd}/$b ]; then
      cp -p $k ${ltspBase}${cpuArch}/root/board-debs/${zd}/
    fi
  done
  sed -i s/'sudo '/''/g ${ltspBase}${cpuArch}/root/board-debs/${zd}/install-linux.sh
  echo "#!/bin/sh"> ${ltspBase}${cpuArch}/root/board-debs/${zd}/do-install-linux.sh
  echo "cd /root/board-debs/${zd}/" >> ${ltspBase}${cpuArch}/root/board-debs/${zd}/do-install-linux.sh
  echo "bash -e /root/board-debs/${zd}/install-linux.sh" >> ${ltspBase}${cpuArch}/root/board-debs/${zd}/do-install-linux.sh
  chmod ugo+rx ${ltspBase}${cpuArch}/root/board-debs/${zd}/do-install-linux.sh
  chroot ${ltspBase}${cpuArch} /root/board-debs/${zd}/do-install-linux.sh

  cd ${ltspBase}${cpuArch}/root/board-debs
  if [ ! -e install-linux.sh ]; then
    ln -s ${zd}/install-linux.sh install-linux.sh
  fi
  cd - > /dev/null
done

cd ${ltspBase}${cpuArch}/boot/

if [ -e ${ltspBase}${cpuArch}/root/board-debs/install-linux.sh ]; then
  true
elif [ -e ${ltspBase}kernel/uImage ]; then
  cp -p ${ltspBase}kernel/uImage .
  chown root:root uImage
elif [ -e ${ltspBase}fw/uImage ]; then
  cp -p ${ltspBase}fw/uImage .
  chown root:root uImage
fi

for f in ${ltspBase}archives/*usb_key_func*.zip ; do
  if [ -e $f ]; then
    unzip -o $f
  fi
done

for f in ${ltspBase}archives/*-boot*.tar.gz ; do
  if [ -e $f ]; then
    tar xzvf $f
  fi
done

cd -

cd ${ltspBase}${cpuArch}/

[ -e ${ltspBase}fw/newroot.tar.gz ] && tar --keep-directory-symlink -xzvf ${ltspBase}fw/newroot.tar.gz

if [ -e ${ltspBase}${cpuArch}/root/board-debs/install-linux.sh ]; then
  true
elif [ -e ${ltspBase}kernel/modules.tar.gz ]; then
  tar xzvf ${ltspBase}kernel/modules.tar.gz
  chown -R root:root lib/modules
elif [ -e ${ltspBase}kernel/modules.tar.xz ]; then
  tar xJvf ${ltspBase}kernel/modules.tar.xz
  chown -R root:root lib/modules
elif [ -e ${ltspBase}fw/modules.tar.gz ]; then
  tar xzvf ${ltspBase}fw/modules.tar.gz
  chown -R root:root lib/modules
fi

for f in ${ltspBase}archives/*debian-*-root*.tar.gz ; do
  tar xzvf $f
done

for f in `ls ${ltspBase}archives/*debian-*${distName}*-init-scripts*.tar.gz` ; do
  tar xzvf $f
done

if [ ${imageOmv} = true ]; then
  if chroot ${ltspBase}${cpuArch} dpkg -s linux-headers-${cpuArch} >/dev/null ; then
    if chroot ${ltspBase}${cpuArch} dpkg -s iscsitarget-dkms >/dev/null ; then
      chroot ${ltspBase}${cpuArch} apt-get install -y openmediavault-iscsitarget
    fi
  fi

omvprfx=openmediavault-${versOmv}
omvpkgv=`chroot ${ltspBase}${cpuArch} dpkg -s openmediavault | grep -E '^Version: ' | cut -d ' ' -f 2 | cut -d '.' -f 1-2`

  for f in ${ltspBase}archives/*${omvprfx}*-root*.tar.gz ; do
    tar xzvf $f
  done

  for p in ${ltspBase}archives/*${omvprfx}*.patch ; do
    f=`echo $p | sed s/-${versOmv}'\..\.'/-${omvpkgv}'.'/g`
    echo try $f
    if [ ! -e $f ]; then
      f=`echo $p | sed s/-${versOmv}'\..\.'/-${versOmv}'.0.'/g`
    fi
    if [ ! -e $f ]; then
      f=$p
    fi
    echo $f
    s=${ltspBase}${cpuArch}/tmp/`basename $f`.done
    if [ ! -e $s ]; then
      patch -p1 < $f
      touch $s
    fi
  done
fi

cd -

chroot ${ltspBase}${cpuArch} umount /proc


sed -i s/'^" let g:skip_defaults_vim = 1'/'let g:skip_defaults_vim = 1'/g ${ltspBase}${cpuArch}/etc/vim/vimrc

sed -i s/'NEED_IDMAPD=.*'/'NEED_IDMAPD=no'/g ${ltspBase}${cpuArch}/etc/default/nfs-common

imageHostnameUpper=`echo $imageHostname | tr a-z A-Z`
sed -i s/'server string = .*'/'server string = '${imageHostnameUpper}' server'/g ${ltspBase}${cpuArch}/etc/samba/smb.conf
sed -i s/'netbios name = .*'/'netbios name = '${imageHostnameUpper}/g ${ltspBase}${cpuArch}/etc/samba/smb.conf

if [ "x${imageEth0Ip}" = "xdhcp" -o "x${imageEth0Ip}" = "x" ]; then
  sed -i s/'egiga0.* netmask 255.255.255.0'/'egiga0'/g ${ltspBase}${cpuArch}/boot/usb_key_func.sh.2
  sed -i 's|#/sbin/dhcpcd egiga0|/sbin/dhcpcd egiga0|g' ${ltspBase}${cpuArch}/boot/usb_key_func.sh.2
elif [ "x${imageEth0Ip}" != "x" ]; then
  sed -i s/'egiga0.* netmask 255.255.255.0'/'egiga0 '${imageEth0Ip}' netmask '${imageEth0Mask}/g ${ltspBase}${cpuArch}/boot/usb_key_func.sh.2
fi

if [ "x${imageEth1Ip}" = "xdhcp" ]; then
  sed -i s/'egiga1.* netmask 255.255.255.0'/'egiga1'/g ${ltspBase}${cpuArch}/boot/usb_key_func.sh.2
  sed -i 's|#/sbin/dhcpcd egiga1|/sbin/dhcpcd egiga1|g' ${ltspBase}${cpuArch}/boot/usb_key_func.sh.2
elif [ "x${imageEth1Ip}" != "x" ]; then
  sed -i s/'egiga1.* netmask 255.255.255.0'/'egiga1 '${imageEth1Ip}' netmask '${imageEth1Mask}/g ${ltspBase}${cpuArch}/boot/usb_key_func.sh.2
else
  sed -i s/'egiga1.* netmask 255.255.255.0'/'egiga1'/g ${ltspBase}${cpuArch}/boot/usb_key_func.sh.2
fi

if [ "x${imageRouter}" != "x" ]; then
  sed -i s/'route add default gw .*'/'route add default gw '${imageRouter}/g ${ltspBase}${cpuArch}/boot/usb_key_func.sh.2
else
  sed -i s/'route add default gw .*'/''/g ${ltspBase}${cpuArch}/boot/usb_key_func.sh.2
fi

sed -i 's|true #/usr/local/bin/zy-fw-get-bin|/usr/local/bin/zy-fw-get-bin|g' ${ltspBase}${cpuArch}/boot/usb_key_func.sh.2
sed -i 's|true #/usr/local/bin/zy-sysdisk-mount|/usr/local/bin/zy-sysdisk-mount|g' ${ltspBase}${cpuArch}/debinit.sh

if [ "${boardModel}" != "onboot" ]; then
  sed -i 's|/usr/local/bin/zy-fw-get-bin|true #/usr/local/bin/zy-fw-get-bin|g' ${ltspBase}${cpuArch}/boot/usb_key_func.sh.2
  sed -i 's|/usr/local/bin/zy-sysdisk-mount|true #/usr/local/bin/zy-sysdisk-mount|g' ${ltspBase}${cpuArch}/debinit.sh
fi

sed -i 's|tar xzf ${FWOUTPATH}/newroot.tar.gz|tar --keep-directory-symlink -xzf ${FWOUTPATH}/newroot.tar.gz|g' ${ltspBase}${cpuArch}/usr/local/bin/zy-init-get

sed -i 's|^/usr/local/bin/start-md.sh|#/usr/local/bin/start-md.sh|g' ${ltspBase}${cpuArch}/debinit.sh
sed -i 's|^/usr/local/bin/mount-md.sh|#/usr/local/bin/mount-md.sh|g' ${ltspBase}${cpuArch}/debinit.sh

if [ ${imageMdMount} = true ]; then
  sed -i 's|#/usr/local/bin/start-md.sh|/usr/local/bin/start-md.sh|g' ${ltspBase}${cpuArch}/debinit.sh

  if [ ${imageOmv} != true ]; then
    sed -i 's|#/usr/local/bin/mount-md.sh|/usr/local/bin/mount-md.sh|g' ${ltspBase}${cpuArch}/debinit.sh
  fi
fi

if [ ${imageOmv} = true ]; then
  if [ ${imageOmvInit} = true ]; then
    sed -i 's|true #omv-confdbadm populate|omv-confdbadm populate|g' ${ltspBase}${cpuArch}/debinit.sh
    sed -i 's|true #omv-confdbadm populate|omv-confdbadm populate|g' ${ltspBase}${cpuArch}/etc/rc.local
    sed -i 's|true #omv-initsystem|omv-initsystem|g' ${ltspBase}${cpuArch}/debinit.sh
    sed -i 's|true #omv-initsystem|omv-initsystem|g' ${ltspBase}${cpuArch}/etc/rc.local
    sed -i 's|#omv-initsystem|omv-initsystem|g' ${ltspBase}${cpuArch}/debinit.sh
    sed -i 's|#omv-initsystem|omv-initsystem|g' ${ltspBase}${cpuArch}/etc/rc.local
  fi
  sed -i 's|#dpkg-reconfigure openmediavault|dpkg-reconfigure openmediavault|g' ${ltspBase}${cpuArch}/etc/rc.local
fi


if [ "${cpuArch:0:3}" != "arm" ]; then
  true
elif [ -e ${ltspBase}${cpuArch}/bin/systemctl.druic -a ! -e ${ltspBase}${cpuArch}/bin/systemctl.distrib ]; then
  chroot ${ltspBase}${cpuArch} mount /proc || true
  echo enable zy-stop
  chroot ${ltspBase}${cpuArch} systemctl enable zy-stop
  if [ -e ${ltspBase}${cpuArch}/lib/systemd/system/zy-fanctrl.timer ]; then
    echo enable zy-fanctrl.timer
    chroot ${ltspBase}${cpuArch} systemctl enable zy-fanctrl.timer
  fi
  chroot ${ltspBase}${cpuArch} umount /proc
  echo divert systemctl
  chroot ${ltspBase}${cpuArch} dpkg-divert --local --rename --add /bin/systemctl
  chroot ${ltspBase}${cpuArch} ln -s /bin/systemctl.druic /bin/systemctl
  if [ ! -e ${ltspBase}${cpuArch}/bin/logger.distrib ]; then
    echo divert logger
    chroot ${ltspBase}${cpuArch} dpkg-divert --local --rename --add /bin/logger
    chroot ${ltspBase}${cpuArch} ln -s /bin/true /bin/logger
  fi
fi


if [ -e ${ltspBase}${cpuArch}/lib/systemd/system/nfs-common.service ]; then
  if [ "x`readlink ${ltspBase}${cpuArch}/lib/systemd/system/nfs-common.service`" = "x/dev/null" ]; then
    rm ${ltspBase}${cpuArch}/lib/systemd/system/nfs-common.service
    #systemctl enable nfs-common
  fi
fi

if [ ! -e ${ltspBase}${cpuArch}/sbin/hotplug ]; then
  cat <<EOFDRUSBHP | tee -a ${ltspBase}${cpuArch}/sbin/hotplug > /dev/null
#!/bin/sh
#echo 'ACTION="'$ACTION'" DEVPATH="'$DEVPATH'" SUBSYSTEM="'$SUBSYSTEM'" SEQNUM="'$SEQNUM'"' >> /var/log/hotplug.log
exit 0
EOFDRUSBHP

  chmod ugo+rx ${ltspBase}${cpuArch}/sbin/hotplug
fi


firstUser=`cat ${ltspBase}${cpuArch}/etc/passwd |grep '504:500' | cut -d ':' -f 1 2>/dev/null`

WriteConfigFile

touch ${ltspBase}${cpuArch}/tmp/configuration.done


make_disk_image ext4 3 $imageName

echo "OK"

