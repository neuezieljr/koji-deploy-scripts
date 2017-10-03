#!/bin/bash -
set -euo pipefail

install_package()
{
    $INSTALLER install -y mock \
                          rpm-build \
                          createrepo \
                          livecd-tools \
                          python-kickstart \
                          pycdio \
                          koji-builder
}

setup_builder_config()
{
    mkdir -p /etc/kojid/backup
    mv /etc/kojid/kojid.conf /etc/kojid/backup/kojid.conf
    sed -e 's,#KOJI_HUB_NAME#,'${KOJI_HUB_NAME}',g' \
        -e 's,#KOJI_DIR#,'${KOJI_DIR}',g' \
	-e 's,#KOJI_BUILDER_CA#,'/etc/kojid/${KOJI_BUILDER_CA}',g' \
	-e 's,#KOJI_SERVER_CA#,'/etc/kojid/${KOJI_SERVER_CA}',g' \
	$KOJI_SETUP_BUILDER_DIR/kojid.conf > /etc/kojid/kojid.conf
}

retrieve_cert_file()
{
    cp /opt/koji-clients/kojibuilder/client.crt /etc/kojid/${KOJI_BUILDER_CA}
    cp /opt/koji-clients/kojibuilder/serverca.crt /etc/kojid/${KOJI_SERVER_CA}
}

! rpm -qa | grep -q koji-builder && \
    install_package

if [ ! -f /etc/kojid/backup/kojid.conf ]; then
    setup_builder_config
    retrieve_cert_file
    systemctl restart kojid
fi
