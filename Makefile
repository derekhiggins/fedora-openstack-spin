all : iso

iso:
	sudo livecd-creator -c fedora-openstack.ks -v --cache=/tmp/cache --releasever=18 -f FedoraOpenStack

test:
	qemu-kvm -cdrom FedoraOpenStack.iso -m 2G

