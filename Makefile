all : FedoraOpenStack.iso

FedoraOpenStack.iso: fedora-openstack.ks
	sudo livecd-creator -c fedora-openstack.ks -v --cache=/tmp/cache --releasever=18 -f FedoraOpenStack --product="Fedora OpenStack Spin" --compression-type=xz --image-type=livecd --title="OpenStack"

test: FedoraOpenStack.iso
	qemu-kvm -cdrom FedoraOpenStack.iso -m 4G

