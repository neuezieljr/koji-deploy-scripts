#!/bin/sh

koji add-tag dist-centos7
koji add-tag --parent dist-centos7 --arches "x86_64" dist-centos7-build

# external repos
koji add-external-repo -t dist-centos7-build dist-centos7-repo http://mirrors.kernel.org/centos/7/os/\$arch/
koji add-external-repo -t dist-centos7-build dist-epel7-repo https://dl.fedoraproject.org/pub/epel/7/\$arch/
koji add-external-repo -t dist-centos7-build dist-epel7-srv-repo https://dl.fedoraproject.org/pub/epel/7Server/\$arch/
koji add-target dist-centos7 dist-centos7-build

# virtual build yum groups
koji add-group dist-centos7-build build
koji add-group dist-centos7-build srpm-build
koji add-group-pkg dist-centos7-build build bash bzip2 coreutils cpio diffutils findutils gawk gcc grep sed gcc-c++ gzip info patch redhat-rpm-config rpm-build shadow-utils tar unzip util-linux-ng which make
koji add-group-pkg dist-centos7-build srpm-build bash cvs gnupg make redhat-rpm-config rpm-build shadow-utils wget rpmdevtools

koji regen-repo dist-centos7-build
