#!/bin/sh
ltspBase=./
cd ${ltspBase} ; ltspBase=`pwd`/ ; cd - > /dev/null

boardModel=nas540
FWGETURL="ftp://ftp.zyxel.com/NAS540/firmware/NAS540_V5.11(AATB.3)C0.zip"
fanSpeed=keep

boardName=nas
cpuArch=armhf
distBrand=Debian
#distName=wheezy
distName=jessie
distURL=http://ftp.us.debian.org/debian
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

distBrandLower=`echo $distBrand | tr A-Z a-z`

if [ $cpuArch = amd64 -o $cpuArch = i386 ]; then
  boardName=pc
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
    BOOT_SIZE_LIMIT=64
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
        mkfs.ext4 -L TC_ROOT -m 0 "${ROOT_LOOP}" > /dev/null
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

    rsync -a "$R/" "${MOUNTDIR}/"
    rsync -a --progress "$R/" "${MOUNTDIR}/"

    rm -rf ${MOUNTDIR}/tmp/* ${MOUNTDIR}/var/tmp/*
    if [ ${GB} -eq 2 ]; then
        sed -i s/'deb-src'/'#deb-src'/g ${MOUNTDIR}/etc/apt/sources.list
        sed -i s/'deb-src'/'#deb-src'/g ${MOUNTDIR}/etc/apt/sources.list.d/*.list || true
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
    fi

    umount "${MOUNTDIR}"
    losetup -d "${ROOT_LOOP}"

    if [ $cpuArch != amd64 -a $cpuArch != i386 ]; then
        echo "Creating images/${IMAGE}.gz ......"
        gzip ${BASEDIR}/${IMAGE}
    fi
}


# ---- main ----

if [ x$1 = xadminpassword ]; then
  admin_password
  exit 0
elif [ x$1 = xuserpassword ]; then
  user_password
  exit 0
elif [ x$1 = xdiskimage ]; then
  make_disk_image ext4 2 $imageName
  exit 0
fi


echo " *** install packages on build host ..."
apt-get install -y debootstrap qemu-user-static binfmt-support whiptail dosfstools rsync patch python-minimal

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
fi


if [ ! -e ${ltspBase}${cpuArch}/tmp/debootstrap.done ]; then
  echo " *** debootstrap ..."

  #--keyring=${ltspEtc}${distKeyringFile}
  debootstrap --arch ${cpuArch} --foreign --variant=minbase --include=locales ${distName} ${ltspBase}${cpuArch} ${distURL}

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

chroot ${ltspBase}${cpuArch} mount -t proc /proc /proc

mkdir -p ${ltspBase}${cpuArch}/root/bin
cp ${ltspBase}dru-nas.txt ${ltspBase}${cpuArch}/root/bin/dru-nas.sh
chmod ugo+rx ${ltspBase}${cpuArch}/root/bin/dru-nas.sh
cp ${ltspBase}dru-omv.txt ${ltspBase}${cpuArch}/root/bin/dru-omv.sh
chmod ugo+rx ${ltspBase}${cpuArch}/root/bin/dru-omv.sh
cp ${ltspBase}dru-usr.txt ${ltspBase}${cpuArch}/root/bin/dru-usr.sh
chmod ugo+rx ${ltspBase}${cpuArch}/root/bin/dru-usr.sh

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

if [ $cpuArch != "armhf" ]; then
  true
elif [ -e ${ltspBase}${cpuArch}/bin/systemctl.druic -a -e ${ltspBase}${cpuArch}/bin/systemctl.distrib ]; then
  chroot ${ltspBase}${cpuArch} rm /bin/systemctl
  chroot ${ltspBase}${cpuArch} dpkg-divert --local --rename --remove /bin/systemctl
fi

chroot ${ltspBase}${cpuArch} systemctl enable ssh
chroot ${ltspBase}${cpuArch} systemctl disable quota

if [ $cpuArch != "armhf" ]; then
	chroot ${ltspBase}${cpuArch} bash -e /root/board-debs/drulininst.sh

	cd ${ltspBase}${cpuArch}
	tar xzvf ${ltspBase}archives/${boardName}-bootloader-${cpuArch}.tar.gz
	cd -
fi


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


echo "precedence ::ffff:0:0/96  100" | tee -a ${ltspBase}${cpuArch}/etc/gai.conf

cat <<EOFDRUSC | tee -a ${ltspBase}${cpuArch}/etc/sysctl.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOFDRUSC


mkdir -p ${ltspBase}${cpuArch}/etc/tmpfiles.d

cat <<EOFDRUTFD | tee ${ltspBase}${cpuArch}/etc/tmpfiles.d/${distBrandLower}.conf
#Type Path        Mode UID  GID  Age Argument
    d    /var/log/apt      0755 root   root - -
    d    /var/log/dist-upgrade   0755 root   root - -
    d    /var/log/fsck     0755 root   root - -
    d    /var/log/lightdm  0755 root   root - -
    d    /var/log/ntpstats 0755 ntp    ntp  - -
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


bootDisk=sda

cat <<EOFDRUFSTAB | tee ${ltspBase}${cpuArch}/etc/fstab > /dev/null
proc            /proc           proc    defaults          0       0
tmpfs           /tmp            tmpfs   defaults          0       0
EOFDRUFSTAB

if [ $cpuArch != "armhf" ]; then
  cat <<EOFDRUFSTAC | tee -a ${ltspBase}${cpuArch}/etc/fstab > /dev/null
tmpfs           /var/log        tmpfs   defaults          0       0
/dev/${bootDisk}1  /boot           vfat    defaults          0       2
/dev/${bootDisk}2  /               ext4    defaults,noatime,nodiratime   0       1
EOFDRUFSTAC
fi



[ ! -e ${ltspBase}${cpuArch}/etc/rc.local-debian ] && cp -p ${ltspBase}${cpuArch}/etc/rc.local ${ltspBase}${cpuArch}/etc/rc.local-debian

cp -p ${ltspBase}${cpuArch}/etc/rc.local-debian ${ltspBase}${cpuArch}/etc/rc.local
sed -i '/^exit 0/ d' ${ltspBase}${cpuArch}/etc/rc.local


if [ $cpuArch = "armhf" ]; then
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


cat <<EOFDRURCLF | tee -a ${ltspBase}${cpuArch}/etc/rc.local > /dev/null

if [ ! -e /etc/.zy-first.done ]; then
EOFDRURCLF


[ $cpuArch = "armhf" ] && echo "  /usr/local/bin/zy-nand-get" >>  ${ltspBase}${cpuArch}/etc/rc.local


cat <<EOFDRURCLO | tee -a ${ltspBase}${cpuArch}/etc/rc.local > /dev/null

  #omv-initsystem
  #dpkg-reconfigure openmediavault-lvm2

  touch /etc/.zy-first.done
fi
EOFDRURCLO


if [ $cpuArch = "armhf" ]; then
cat <<EOFDRURCLS | tee -a ${ltspBase}${cpuArch}/etc/rc.local > /dev/null

/sbin/buzzerc -t 1
/sbin/setLED SYS OFF
EOFDRURCLS
fi


cat <<EOFDRURCLZ | tee -a ${ltspBase}${cpuArch}/etc/rc.local > /dev/null

touch /tmp/.dru-boot.done
EOFDRURCLZ


echo "exit 0" >>  ${ltspBase}${cpuArch}/etc/rc.local



sed -i s/'RSYNC_ENABLE=.*'/'RSYNC_ENABLE=true'/g ${ltspBase}${cpuArch}/etc/default/rsync

[ ! -e ${ltspBase}${cpuArch}/etc/samba/smb.conf-debian ] && mv ${ltspBase}${cpuArch}/etc/samba/smb.conf ${ltspBase}${cpuArch}/etc/samba/smb.conf-debian


cp -p ${ltspBase}scripts/zy-fw-get-bin ${ltspBase}${cpuArch}/usr/local/bin/

case ${boardModel} in
    nsa310a) FWGETURL="ftp://ftp.zyxel.com/NSA310a/firmware/NSA310_4.40(AFK.0)C0.zip" ;;
    nsa310s) FWGETURL="ftp://ftp.zyxel.com/NSA310S/firmware/NSA310S_V4.75(AALH.1)C0.zip" ;;
    nsa320s) FWGETURL="ftp://ftp.zyxel.com/NSA320S/firmware/NSA320S_V4.75(AANV.1)C0.zip" ;;
    nsa325)  FWGETURL="ftp://ftp.zyxel.com/NSA325/firmware/NSA325_V4.81(AAAJ.0)C0.zip" ;;
    nas326)  FWGETURL="ftp://ftp.zyxel.com/NAS326/firmware/NAS326_V5.11(AAZF.4)C0.zip" ;;
    nas520)  FWGETURL="ftp://ftp.zyxel.com/NAS520/firmware/NAS520_V5.11(AASZ.3)C0.zip" ;;
    nas540)  FWGETURL="ftp://ftp.zyxel.com/NAS540/firmware/NAS540_V5.11(AATB.3)C0.zip" ;;
    nas542)  FWGETURL="ftp://ftp.zyxel.com/NAS542/firmware/NAS542_V5.11(ABAG.3)C0.zip" ;;
esac

if [ "${boardModel}" != "onboot" ]; then
  ${ltspBase}scripts/zy-fw-extract - ${ltspBase}fw "${FWGETURL}"
fi

for z in `ls ${ltspBase}kernel/linux-image-*-${cpuArch}.zip` ; do
  zd=`basename ${z}`
  zd=${zd/linux-image-/}
  zd=${zd/-${cpuArch}.zip/}
  mkdir -p ${ltspBase}${cpuArch}/root/board-debs/${zd}
  cd ${ltspBase}${cpuArch}/root/board-debs/${zd}
  unzip -o ${z}
  cd - > /dev/null
  chroot ${ltspBase}${cpuArch} /root/board-debs/${zd}/install-linux.sh

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

unzip -o ${ltspBase}archives/*usb_key_func*.zip
for f in ${ltspBase}archives/*-boot*.tar.gz ; do
  tar xzvf $f
done
cd -

cd ${ltspBase}${cpuArch}/

[ -e ${ltspBase}fw/newroot.tar.gz ] && tar xzvf ${ltspBase}fw/newroot.tar.gz

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

if [ ${imageOmv} = true ]; then
  for f in ${ltspBase}archives/*openmediavault-*-root*.tar.gz ; do
    tar xzvf $f
  done

  for f in ${ltspBase}archives/*openmediavault-*.patch ; do
    s=${ltspBase}${cpuArch}/tmp/`basename $f`.done
    if [ ! -e $s ]; then
      patch -p1 < $f
      touch $s
    fi
  done
fi

cd -


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
    sed -i 's|#omv-initsystem|omv-initsystem|g' ${ltspBase}${cpuArch}/debinit.sh
    sed -i 's|#omv-initsystem|omv-initsystem|g' ${ltspBase}${cpuArch}/etc/rc.local
  fi
  sed -i 's|#dpkg-reconfigure openmediavault|dpkg-reconfigure openmediavault|g' ${ltspBase}${cpuArch}/etc/rc.local
fi


if [ $cpuArch != "armhf" ]; then
  true
elif [ -e ${ltspBase}${cpuArch}/bin/systemctl.druic -a ! -e ${ltspBase}${cpuArch}/bin/systemctl.distrib ]; then
  chroot ${ltspBase}${cpuArch} systemctl enable zy-stop
  chroot ${ltspBase}${cpuArch} dpkg-divert --local --rename --add /bin/systemctl
  chroot ${ltspBase}${cpuArch} ln -s /bin/systemctl.druic /bin/systemctl
fi


firstUser=`cat ${ltspBase}${cpuArch}/etc/passwd |grep '504:500' | cut -d ':' -f 1 2>/dev/null`

cat <<EOFDRUBCF | tee ${ltspBase}${cpuArch}/etc/${distBrandLower}-build.conf
boardModel=${boardModel}
FWGETURL="${FWGETURL}"
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
EOFDRUBCF

mkdir -p ${ltspBase}etc
cp -p ${ltspBase}${cpuArch}/etc/${distBrandLower}-build.conf ${ltspBase}etc/

touch ${ltspBase}${cpuArch}/tmp/configuration.done


make_disk_image ext4 2 $imageName

echo "OK"

