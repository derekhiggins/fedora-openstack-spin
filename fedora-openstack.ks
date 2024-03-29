# fedora-openstack.ks
#
# Description:
# - Fedora OpenStack Spin
#  Installs an OpenStack Environment in a vm
#
# Maintainer(s):
# - Matthias Runge <mrunge@fedoraproject.org>

lang en_US.UTF-8
keyboard us
timezone US/Eastern
auth --useshadow --enablemd5
# we need to catch selinux errors
selinux --permissive
firewall --enabled --service=mdns
xconfig --startxonboot
part / --size 4096 --fstype ext4
part /var/lib/libvirt --size 12288 --fstype ext4
services --enabled=NetworkManager --disabled=network,sshd

#repo --name=rawhide --mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=rawhide&arch=$basearch
#repo --name=fedora --mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=fedora-$releasever&arch=$basearch
#repo --name=updates --mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=updates-released-f$releasever&arch=$basearch
#repo --name=updates-testing --mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=updates-testing-f$releasever&arch=$basearch
repo --name=euler --baseurl=http://euler/fedora/releases
repo --name=euler-testing --baseurl=http://euler/fedora/updates/testing
repo --name=euler-updates --baseurl=http://euler/fedora/updates/18
%packages
@base-x
@base
@core
@fonts
@input-methods
@admin-tools
@hardware-support

# Explicitly specified here:
# <notting> walters: because otherwise dependency loops cause yum issues.
kernel

# The point of a live image is to install
anaconda
isomd5sum
# grub-efi and grub2 and efibootmgr so anaconda can use the right one on install. 
grub-efi
grub2
efibootmgr

# fpaste is very useful for debugging and very small
fpaste

# openstack packages
libvirt-daemon
virt-viewer
novnc
openstack-nova
openstack-nova-novncproxy
openstack-swift
openstack-swift-doc
openstack-swift-proxy
openstack-swift-account
openstack-swift-container
openstack-swift-object
openstack-cinder
openstack-glance
openstack-utils
openstack-dashboard
openstack-quantum
openstack-tempo
openstack-quantum-linuxbridge
openstack-quantum-openvswitch
python-cinder 
python-cinderclient
python-glance
python-nova
python-keystone
python-passlib
openstack-keystone
openstack-packstack
mysql-server
qpid-cpp-server-daemon
qpid-cpp-server
memcached 
nbd
sudo
avahi
virt-what
virt-manager
virt-viewer
openssh-server
spice-gtk
gtk-vnc-python
net-tools
puppet
%end

%post
# FIXME: it'd be better to get this installed from a package
cat > /etc/rc.d/init.d/livesys << EOF
#!/bin/bash
#
# live: Init script for live image
#
# chkconfig: 345 00 99
# description: Init script for live image.

. /etc/init.d/functions

if ! strstr "\`cat /proc/cmdline\`" liveimg || [ "\$1" != "start" ]; then
    exit 0
fi

if [ -e /.liveimg-configured ] ; then
    configdone=1
fi

exists() {
    which \$1 >/dev/null 2>&1 || return
    \$*
}

touch /.liveimg-configured

# Make sure we don't mangle the hardware clock on shutdown
ln -sf /dev/null /etc/systemd/system/hwclock-save.service

livedir="LiveOS"
for arg in \`cat /proc/cmdline\` ; do
  if [ "\${arg##live_dir=}" != "\${arg}" ]; then
    livedir=\${arg##live_dir=}
    return
  fi
done

# enable swaps unless requested otherwise
swaps=\`blkid -t TYPE=swap -o device\`
if ! strstr "\`cat /proc/cmdline\`" noswap && [ -n "\$swaps" ] ; then
  for s in \$swaps ; do
    action "Enabling swap partition \$s" swapon \$s
  done
fi
if ! strstr "\`cat /proc/cmdline\`" noswap && [ -f /run/initramfs/live/\${livedir}/swap.img ] ; then
  action "Enabling swap file" swapon /run/initramfs/live/\${livedir}/swap.img
fi

mountPersistentHome() {
  # support label/uuid
  if [ "\${homedev##LABEL=}" != "\${homedev}" -o "\${homedev##UUID=}" != "\${homedev}" ]; then
    homedev=\`/sbin/blkid -o device -t "\$homedev"\`
  fi

  # if we're given a file rather than a blockdev, loopback it
  if [ "\${homedev##mtd}" != "\${homedev}" ]; then
    # mtd devs don't have a block device but get magic-mounted with -t jffs2
    mountopts="-t jffs2"
  elif [ ! -b "\$homedev" ]; then
    loopdev=\`losetup -f\`
    if [ "\${homedev##/run/initramfs/live}" != "\${homedev}" ]; then
      action "Remounting live store r/w" mount -o remount,rw /run/initramfs/live
    fi
    losetup \$loopdev \$homedev
    homedev=\$loopdev
  fi

  # if it's encrypted, we need to unlock it
  if [ "\$(/sbin/blkid -s TYPE -o value \$homedev 2>/dev/null)" = "crypto_LUKS" ]; then
    echo
    echo "Setting up encrypted /home device"
    plymouth ask-for-password --command="cryptsetup luksOpen \$homedev EncHome"
    homedev=/dev/mapper/EncHome
  fi

  # and finally do the mount
  mount \$mountopts \$homedev /home
  # if we have /home under what's passed for persistent home, then
  # we should make that the real /home.  useful for mtd device on olpc
  if [ -d /home/home ]; then mount --bind /home/home /home ; fi
  [ -x /sbin/restorecon ] && /sbin/restorecon /home
  if [ -d /home/liveuser ]; then USERADDARGS="-M" ; fi
}

findPersistentHome() {
  for arg in \`cat /proc/cmdline\` ; do
    if [ "\${arg##persistenthome=}" != "\${arg}" ]; then
      homedev=\${arg##persistenthome=}
      return
    fi
  done
}

if strstr "\`cat /proc/cmdline\`" persistenthome= ; then
  findPersistentHome
elif [ -e /run/initramfs/live/\${livedir}/home.img ]; then
  homedev=/run/initramfs/live/\${livedir}/home.img
fi

# if we have a persistent /home, then we want to go ahead and mount it
if ! strstr "\`cat /proc/cmdline\`" nopersistenthome && [ -n "\$homedev" ] ; then
  action "Mounting persistent /home" mountPersistentHome
fi

# make it so that we don't do writing to the overlay for things which
# are just tmpdirs/caches
mount -t tmpfs -o mode=0755 varcacheyum /var/cache/yum
# also create space for mysql data
mount -t tmpfs -o mode=0755 varlibmysql /var/lib/mysql
chown mysql:mysql /var/lib/mysql
mount -t tmpfs tmp /tmp
mount -t tmpfs vartmp /var/tmp
[ -x /sbin/restorecon ] && /sbin/restorecon /var/cache/yum /tmp /var/tmp >/dev/null 2>&1

# add fedora user with no passwd
action "Adding live user" useradd \$USERADDARGS -c "Live System User" liveuser
echo "liveuser ALL = (ALL) NOPASSWD: ALL" > /etc/sudoers.d/openstack-spin
passwd -d liveuser > /dev/null

# turn off firstboot for livecd boots
systemctl --no-reload disable firstboot-text.service 2> /dev/null || :
systemctl --no-reload disable firstboot-graphical.service 2> /dev/null || :
systemctl stop firstboot-text.service 2> /dev/null || :
systemctl stop firstboot-graphical.service 2> /dev/null || :

# don't use prelink on a running live image
sed -i 's/PRELINKING=yes/PRELINKING=no/' /etc/sysconfig/prelink &>/dev/null || :

# turn off mdmonitor by default
systemctl --no-reload disable mdmonitor.service 2> /dev/null || :
systemctl --no-reload disable mdmonitor-takeover.service 2> /dev/null || :
systemctl stop mdmonitor.service 2> /dev/null || :
systemctl stop mdmonitor-takeover.service 2> /dev/null || :

# don't enable the gnome-settings-daemon packagekit plugin
gsettings set org.gnome.settings-daemon.plugins.updates active 'false' || :

# don't start cron/at as they tend to spawn things which are
# disk intensive that are painful on a live image
systemctl --no-reload disable crond.service 2> /dev/null || :
systemctl --no-reload disable atd.service 2> /dev/null || :
systemctl stop crond.service 2> /dev/null || :
systemctl stop atd.service 2> /dev/null || :

# and hack so that we eject the cd on shutdown if we're using a CD...
if strstr "\`cat /proc/cmdline\`" CDLABEL= ; then
  cat >> /sbin/halt.local << FOE
#!/bin/bash
# XXX: This often gets stuck during shutdown because /etc/init.d/halt
#      (or something else still running) wants to read files from the block\
#      device that was ejected.  Disable for now.  Bug #531924
# we want to eject the cd on halt, but let's also try to avoid
# io errors due to not being able to get files...
#cat /sbin/halt > /dev/null
#cat /sbin/reboot > /dev/null
#/usr/sbin/eject -p -m \$(readlink -f /run/initramfs/livedev) >/dev/null 2>&1
#echo "Please remove the CD from your drive and press Enter to finish restarting"
#read -t 30 < /dev/console
FOE
chmod +x /sbin/halt.local
fi

EOF

# bah, hal starts way too late
cat > /etc/rc.d/init.d/livesys-late << EOF
#!/bin/bash
#
# live: Late init script for live image
#
# chkconfig: 345 99 01
# description: Late init script for live image.

. /etc/init.d/functions

if ! strstr "\`cat /proc/cmdline\`" liveimg || [ "\$1" != "start" ] || [ -e /.liveimg-late-configured ] ; then
    exit 0
fi
exists() {
    which \$1 >/dev/null 2>&1 || return
    \$*
}

touch /.liveimg-late-configured

# read some variables out of /proc/cmdline
for o in \`cat /proc/cmdline\` ; do
    case \$o in
    ks=*)
        ks="--kickstart=\${o#ks=}"
        ;;
    xdriver=*)
        xdriver="\${o#xdriver=}"
        ;;
    esac
done

# if liveinst or textinst is given, start anaconda
if strstr "\`cat /proc/cmdline\`" liveinst ; then
   plymouth --quit
   /usr/sbin/liveinst \$ks
fi
if strstr "\`cat /proc/cmdline\`" textinst ; then
   plymouth --quit
   /usr/sbin/liveinst --text \$ks
fi

# configure X, allowing user to override xdriver
if [ -n "\$xdriver" ]; then
   cat > /etc/X11/xorg.conf.d/00-xdriver.conf <<FOE
Section "Device"
        Identifier      "Videocard0"
        Driver  "\$xdriver"
EndSection
FOE
fi

echo "nbd" > /etc/modules-load.d/nbd.conf
sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
setenforce permissive

systemctl start sshd.service
ssh-keygen -N "" -f /root/.ssh/id_rsa
cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
# packstack answer file
cat > /root/packstack-answer-file << EOP
[general]
CONFIG_DEBUG=y
CONFIG_GLANCE_INSTALL=y
CONFIG_CINDER_INSTALL=n
CONFIG_NOVA_INSTALL=y
CONFIG_HORIZON_INSTALL=y
CONFIG_SWIFT_INSTALL=n
CONFIG_CLIENT_INSTALL=y
CONFIG_SSH_KEY=/root/.ssh/id_rsa.pub
CONFIG_MYSQL_HOST=127.0.0.1
CONFIG_MYSQL_USER=root
CONFIG_MYSQL_PW=mypwd
CONFIG_QPID_HOST=127.0.0.1
CONFIG_KEYSTONE_HOST=127.0.0.1
CONFIG_KEYSTONE_ADMINTOKEN=0bcf6981416e475398775aee4798a221
CONFIG_KEYSTONE_ADMINPASSWD=fe5f5c
CONFIG_GLANCE_HOST=127.0.0.1
CONFIG_CINDER_HOST=127.0.0.1
CONFIG_NOVA_API_HOST=127.0.0.1
CONFIG_NOVA_CERT_HOST=127.0.0.1
CONFIG_NOVA_VNCPROXY_HOST=127.0.0.1
CONFIG_NOVA_COMPUTE_HOSTS=127.0.0.1
CONFIG_LIBVIRT_TYPE=kvm
CONFIG_NOVA_COMPUTE_PRIVIF=eth0
CONFIG_NOVA_NETWORK_HOST=127.0.0.1
CONFIG_NOVA_NETWORK_PUBIF=eth0
CONFIG_NOVA_NETWORK_PRIVIF=eth0
CONFIG_NOVA_NETWORK_FIXEDRANGE=192.168.32.0/22
CONFIG_NOVA_NETWORK_FLOATRANGE=10.3.4.0/22
CONFIG_NOVA_SCHED_HOST=127.0.0.1
CONFIG_OSCLIENT_HOST=127.0.0.1
CONFIG_HORIZON_HOST=127.0.0.1
CONFIG_HORIZON_SECRET_KEY=8d2408c246cc4503a89e444ebbcc3650
CONFIG_SWIFT_PROXY_HOSTS=127.0.0.1
CONFIG_SWIFT_STORAGE_HOSTS=127.0.0.1
CONFIG_SWIFT_STORAGE_ZONES=1
CONFIG_SWIFT_STORAGE_REPLICAS=1
CONFIG_SWIFT_STORAGE_FSTYPE=ext4
CONFIG_USE_EPEL=n
CONFIG_REPO=
CONFIG_RH_USERNAME=
CONFIG_RH_PASSWORD=
EOP

cat > /root/.my.cnf << EOM
[client]
password="mypwd"
EOM

systemctl start mysqld.service
mysqladmin password mypwd

export HOME=/root
packstack --answer-file=/root/packstack-answer-file
#rm -f /root/keyfile
#rm -f /root/keyfile.pub

# fire up openstack services
#systemctl start openstack-cinder-api.service
#systemctl start openstack-cinder-scheduler.service
#systemctl start openstack-cinder-volume.service
systemctl start openstack-glance-api.service
systemctl start openstack-glance-registry.service
systemctl start openstack-glance-registry.service
systemctl start openstack-keystone.service
systemctl start openstack-nova-api.service
systemctl start openstack-nova-cert.service
systemctl start openstack-nova-compute.service
systemctl start openstack-nova-consoleauth.service
systemctl start openstack-nova-console.service
systemctl start openstack-nova-metadata-api.service
systemctl start openstack-nova-scheduler.service
systemctl start openstack-nova-xvpvncproxy.service
systemctl start openstack-swift-account.service
systemctl start "openstack-swift-account@.service"
systemctl start openstack-swift-container.service
systemctl start "openstack-swift-container@.service"
systemctl start openstack-swift-object.service
systemctl start "openstack-swift-object@.service"
systemctl start openstack-swift-proxy.service

EOF

chmod 755 /etc/rc.d/init.d/livesys
/sbin/restorecon /etc/rc.d/init.d/livesys
/sbin/chkconfig --add livesys

chmod 755 /etc/rc.d/init.d/livesys-late
/sbin/restorecon /etc/rc.d/init.d/livesys-late
/sbin/chkconfig --add livesys-late

# work around for poor key import UI in PackageKit
rm -f /var/lib/rpm/__db*
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-fedora
echo "Packages within this LiveCD"
rpm -qa
# Note that running rpm recreates the rpm db files which aren't needed or wanted
rm -f /var/lib/rpm/__db*

# go ahead and pre-make the man -k cache (#455968)
/usr/bin/mandb

# save a little bit of space at least...
rm -f /boot/initramfs*
# make sure there aren't core files lying around
rm -f /core*

# convince readahead not to collect
# FIXME: for systemd
%end

# fire up servicesop

%post --nochroot
cp $INSTALL_ROOT/usr/share/doc/*-release-*/GPL $LIVE_ROOT/GPL

# only works on x86, x86_64
if [ "$(uname -i)" = "i386" -o "$(uname -i)" = "x86_64" ]; then
  if [ ! -d $LIVE_ROOT/LiveOS ]; then mkdir -p $LIVE_ROOT/LiveOS ; fi
  cp /usr/bin/livecd-iso-to-disk $LIVE_ROOT/LiveOS
fi
%end

