#!/bin/sh
DISTRO=$(. /etc/os-release ; echo $ID)
RELEASE=$(. /etc/os-release; echo $VERSION_ID)
TAG=${DISTRO}-${RELEASE}

init_common()
{
    koji add-tag ${TAG}
    koji add-tag --parent ${TAG} --arches "x86_64" ${TAG}-build

    # external repos
    koji add-target ${TAG} ${TAG}-build

    # virtual build yum groups
    koji add-group ${TAG}-build build
    koji add-group ${TAG}-build srpm-build
    koji add-group ${TAG}-build livecd-build
    koji add-group ${TAG}-build livemedia-build
    koji add-group ${TAG}-build appliance-build

}

rollback()
{
    koji remove-tag ${TAG}-build
    koji remove-tag ${TAG}
    koji remove-external-repo ${TAG}-repo
}

run_centos_test()
{
    init_common

    # external repos
    koji add-external-repo -t ${TAG}-build ${TAG}-repo http://mirrors.kernel.org/centos/${RELEASE}/os/\$arch/
    koji add-external-repo -t ${TAG}-build epel${RELEASE}-repo https://dl.fedoraproject.org/pub/epel/${RELEASE}/\$arch/
    koji add-external-repo -t ${TAG}-build epel${RELEASE}-srv-repo https://dl.fedoraproject.org/pub/epel/${RELEASE}Server/\$arch/

    koji add-group-pkg ${TAG}-build build \
         bash bzip2 coreutils cpio diffutils findutils gawk gcc grep \
         tar sed gcc-c++ gzip info patch redhat-rpm-config rpm-build \
         shadow-utils unzip util-linux-ng which make

    koji add-group-pkg ${TAG}-build srpm-build \
         bash cvs gnupg make redhat-rpm-config rpm-build wget \
         shadow-utils rpmdevtools

    koji regen-repo ${TAG}-build
}

run_fedora_test()
{
    init_common

    # external repos
    koji add-external-repo -t ${TAG}-build ${TAG}-repo http://mirrors.kernel.org/fedora/releases/${RELEASE}/Everything/\$arch/os/

    koji add-group-pkg ${TAG}-build build \
         bash bzip2 coreutils cpio diffutils fedora-release findutils \
         gawk gcc gcc-c++ grep gzip info make patch redhat-rpm-config \
         rpm-build sed shadow-utils tar unzip util-linux which xz

    koji add-group-pkg ${TAG}-build srpm-build \
         bash fedora-release fedpkg-minimal gnupg2 redhat-rpm-config \
         rpm-build shadow-utils

    koji add-group-pkg ${TAG}-build livecd-build \
         bash coreutils fedora-logos fedora-release livecd-tools \
         policycoreutils python-dbus sed selinux-policy-targeted \
         shadow-utils squashfs-tools sssd-client tar unzip \
         util-linux which yum


    koji add-group-pkg ${TAG}-build livemedia-build \
         bash coreutils glibc-all-langpacks lorax-lmc-novirt \
         selinux-policy-targeted shadow-utils util-linux

    koji add-group-pkg ${TAG}-build appliance-build \
         appliance-tools bash coreutils grub parted perl policycoreutils \
         selinux-policy shadow-utils sssd-client

    koji regen-repo ${TAG}-build
}

while [ $1 ]; do
    case "$1" in
        --distro) shift; DISTRO=$1 ;;
        --release) shift; RELEASE=$1 ;;
    esac
    shift
done

set -euo pipefail

[ "x$DISTRO" = "xfedora" ] && run_fedora_test
[ "x$DISTRO" = "xcentos" ] && run_centos_test
