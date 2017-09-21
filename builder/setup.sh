#!/bin/bash -
set -euo pipefail

install_package()
{
    dnf install mock \
                rpm-build \
                createrepo \
                koji-builder
}

setup_config()
{
    mv /etc/kojid.conf /etc/kojid.conf.prev
    cat /etc/kojid.conf.prev | \
        sed -e '/^;/d' -e '/^$/d' |\
        sed -e '/server=/d' | \
        sed -e '/user=/d' | \
        sed -e '/topurl=/d' | \
        sed -e '/workdir=/d' | \
        sed -e '/topdir=/d' | \
        sed -e '/cert=/d' | \
        sed -e '/ca=/d' | \
        sed -e '/serverca=/d' > /etc/kojid.conf

    cat <<EOF >> /etc/kojid.conf
; The URL for the xmlrpc server
server=http://koji-hub/kojihub

; the username has to be the same as what you used with add-host
; in this example follow as below
user = kojibuilder

; The URL for the file access
topurl=http://koji-hub/kojifiles

; The directory root for temporary storage
workdir=/tmp/koji

; The directory root where work data can be found from the koji hub
topdir=/mnt/koji

;client certificate
; This should reference the builder certificate we created on the kojihub CA, for kojibuilder
; ALSO NOTE: This is the PEM file, NOT the crt
cert = /etc/kojid/kojibuilder.crt

;certificate of the CA that issued the client certificate
ca = /etc/kojid/koji_client_ca_cert.crt

;certificate of the CA that issued the HTTP server certificate
serverca = /etc/kojid/koji_server_ca_cert.crt
EOF

}

retrieve_cert_file()
{
    SERVER=koji-master.local
    scp $SERVER:/opt/koji-client/kojibuilder/client.crt /etc/kojid/kojibuilder.crt
    scp $SERVER:/opt/koji-client/kojibuilder/clientca.crt /etc/kojid/koji_client_ca_cert.crt
    scp $SERVER:/opt/koji-client/kojibuilder/serverca.crt /etc/kojid/koji_server_ca_cert.crt
}

install_package
setup_config
retrieve_cert_file
