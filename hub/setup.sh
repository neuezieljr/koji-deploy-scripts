#!/bin/bash
set -euo pipefail
SERVER=koji-master.local

install_package()
{
    # Server side packages installation
    dnf install -y  httpd \
                    mod_ssl \
                    postgresql-server \
                    mod_wsgi
    dnf install -y koji-hub
}

create_certification()
{
    SERVER=koji-master.local

    mkdir -p /etc/pki/koji/{certs,private,confs}
    touch /etc/pki/koji/index.txt
    echo 01 > /etc/pki/koji/serial

    cp -f openssl.cnf /etc/pki/koji/koji-ssl.cnf

    cd /etc/pki/koji

    openssl genrsa -out private/koji_ca_cert.key 2048
    openssl req -new -x509 \
                -subj "/C=US/ST=Massachusetts/L=Westford/O=RedHat, Inc./OU=PNT/CN=$SERVER" \
                -days 3650 -key private/koji_ca_cert.key -out koji_ca_cert.crt -extensions v3_ca \
                -config <(cat koji-ssl.cnf | sed "s/email:move/DNS.1:localhost,DNS.2:$SERVER,email:move/g")

    cp private/koji_ca_cert.key private/kojihub.key
    cp koji_ca_cert.crt certs/kojihub.crt

    cd -
}

setup_database()
{
    # Initial DB
    su - postgres -c "PGDATA=/var/lib/pgsql/data initdb"
    systemctl enable postgresql
    systemctl start postgresql

    useradd -G postgres -u 2000 -M -N -d /var/run -s /bin/bash koji
    su - postgres -c "createuser --no-superuser --no-createrole --no-createdb koji"
    su - postgres -c "createdb -O koji koji"
    su - postgres -c "psql -c \"alter user koji with encrypted password 'koji';\""

    su - koji -c "psql koji koji < /usr/share/doc/koji/docs/schema.sql"
}

setup_hub_config()
{
    CONFDIR=/etc/httpd/conf.d
    mkdir -p /var/log/httpd
    chown apache.apache -R /var/log/httpd
    mkdir -p $CONFDIR/backup

    mv $CONFDIR/ssl.conf $CONFDIR/backup/ssl.conf
    cat httpd-ssl.conf | \
        sed -e 's,#SERVER_NAME#,'${SERVER}',g' \
            -e 's,#KOJI_HUB_CRT#,'/etc/pki/koji/certs/kojihub.crt',g' \
            -e 's,#KOJI_HUB_KEY#,'/etc/pki/koji/private/kojihub.key',g' \
            -e 's,#KOJI_CA_CERT#,'/etc/pki/koji/koji_ca_cert.crt',g' \
            > $CONFDIR/ssl.conf

    for conffile in kojihub.conf kojiweb.conf; do
        [ ! -f $CONFDIR/$conffile ] && continue
        mv $CONFDIR/$conffile $CONFDIR/backup/$conffile
        cat $CONFDIR/backup/$conffile | \
	    sed '/<Location \/kojihub\/ssllogin>/,/<\/Location>/s,# ,,g' \
	    > $CONFDIR/$conffile
    done

    cat <<EOF > /etc/koji-hub/hub.conf.d/kogi-db
DBName = koji
DBUser = koji
DBPass = koji
KojiWebURL = http://${SERVER}/koji
EnableMaven = True
EnableWin = True
KojiDebug = On
KojiTraceback = extended
DNUsernameComponent = CN
ProxyDNs = $(cat /etc/pki/koji/index.txt | awk /kojiweb/'{print substr($0, index($0,$5))}')
EOF
}

! rpm -qa | grep -q koji-hub && \
	install_package

[ ! -f /etc/pki/koji/private/kojihub.key ] && \
	create_certification

! su - koji -c "psql -c \"select * from users\"" > /dev/null 2>&1 && \
        setup_database

[ ! -f /etc/httpd/conf.d/ssl.conf.orig ] && \
	setup_hub_config
