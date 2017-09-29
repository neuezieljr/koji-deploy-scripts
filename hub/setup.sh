#!/bin/bash
set -euo pipefail

env
export

install_package()
{
    # Server side packages installation
    $INSTALLER install -y httpd \
	                  mod_ssl \
			  mod_wsgi \
	                  postgresql-server

    $INSTALLER install -y koji-hub \
	                  koji-web
}

create_certification()
{
    mkdir -p /etc/pki/koji/{certs,private,confs}
    touch /etc/pki/koji/index.txt
    echo 01 > /etc/pki/koji/serial

    cp -f $KOJI_SETUP_HUB_DIR/openssl.cnf /etc/pki/koji/koji-ssl.cnf

    cd /etc/pki/koji

    openssl genrsa -out private/koji_ca_cert.key 2048
    openssl req -new -x509 \
                -subj "/C=US/ST=Massachusetts/L=Westford/O=RedHat, Inc./OU=PNT/CN=$KOJI_HUB_NAME" \
                -days 3650 -key private/koji_ca_cert.key -out koji_ca_cert.crt -extensions v3_ca \
		-config <(cat koji-ssl.cnf | \
		    sed "s/email:move/DNS.1:localhost,DNS.2:$KOJI_HUB_NAME,DNS.3:$KOJI_WEB_NAME,email:move/g")

    cp private/koji_ca_cert.key private/kojihub.key
    cp koji_ca_cert.crt certs/kojihub.crt

    cd -
}

create_koji_account()
{
    for user in ${KOJI_USERS//,/ }
    do
        IFS=: read u g < <(echo $user)
	echo "Create $g account $u"
	$KOJI_SETUP_HUB_DIR/adduser.sh $u $g
    done
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

    su - koji -c "psql koji koji < /usr/share/doc/koji*/docs/schema.sql"
}

setup_server()
{
    HTTP_CONF_DIR=/etc/httpd/conf.d
    HTTP_CONF_BACKUP_DIR=$HTTP_CONF_DIR/backup

    [ ! -d $HTTP_CONF_BACKUP_DIR ] && \
	mkdir -p $HTTP_CONF_BACKUP_DIR

    setup_http_config
    setup_hub_config
    setup_web_config

    mkdir -p $KOJI_DIR/{packages,repos,work,scratch}
    chown -R apache.apache $KOJI_DIR

    #Check selinux mode
    if [ "x$SELINUX" = "xenabled" ]; then
	setsebool -P allow_httpd_anon_write=1
	chcon -R -t public_content_rw_t $KOJI_DIR
    fi

    systemctl enable httpd
    systemctl restart httpd
}

setup_http_config()
{
    KOJI_HTTPS_CONF="${KOJI_SETUP_HUB_DIR}/httpd.conf/ssl.conf.${OS}"
    KOJI_WEB_CRT=/etc/pki/koji/certs/kojiweb.crt
    KOJI_HUB_CRT=/etc/pki/koji/certs/kojihub.crt
    KOJI_HUB_KEY=/etc/pki/koji/private/kojihub.key
    KOJI_CA_CERT=/etc/pki/koji/koji_ca_cert.crt

    mkdir -p /var/log/httpd
    chown apache.apache -R /var/log/httpd

    mv $HTTP_CONF_DIR/ssl.conf $HTTP_CONF_BACKUP_DIR/ssl.conf
    cat $KOJI_HTTPS_CONF | \
        sed -e 's,#KOJI_HUB_NAME#,'${KOJI_HUB_NAME}',g' \
            -e 's,#KOJI_HUB_CRT#,'${KOJI_HUB_CRT}',g' \
            -e 's,#KOJI_HUB_KEY#,'${KOJI_HUB_KEY}',g' \
            -e 's,#KOJI_CA_CERT#,'${KOJI_CA_CERT}',g' \
        > $HTTP_CONF_DIR/ssl.conf

    echo "ServerName ${KOJI_HUB_NAME}:80" > $HTTP_CONF_DIR/server.conf
}

setup_hub_config()
{
    if [ -f $HTTP_CONF_DIR/kojihub.conf ]; then
        mv $HTTP_CONF_DIR/kojihub.conf $HTTP_CONF_BACKUP_DIR/kojihub.conf
        sed -e 's,#KOJI_DIR#,'${KOJI_DIR}',g' \
            $KOJI_SETUP_HUB_DIR/httpd.conf/kojihub.conf > $HTTP_CONF_DIR/kojihub.conf
    fi

    mkdir -p /etc/koji-hub/backup
    mv /etc/koji-hub/hub.conf /etc/koji-hub/backup/hub.conf
    cat $KOJI_SETUP_HUB_DIR/kojihub.conf | \
        sed -e 's,#KOJI_HUB_NAME#,'${KOJI_HUB_NAME}',g' \
            -e 's,#KOJI_WEB_NAME#,'${KOJI_WEB_NAME}',g' \
	    -e 's,#KOJI_DIR#,'${KOJI_DIR}',g' \
            -e 's,#SSL_PROXY_DN#,'"$(awk /kojiweb/'{print substr($0, index($0,$5))}' /etc/pki/koji/index.txt | sed 's/,/\\,/g')"',' \
        > /etc/koji-hub/hub.conf
}

setup_web_config()
{
    if [ -f $HTTP_CONF_DIR/kojiweb.conf ]; then
        mv $HTTP_CONF_DIR/kojiweb.conf $HTTP_CONF_BACKUP_DIR/kojiweb.conf
        cp $KOJI_SETUP_WEB_DIR/httpd.conf/kojiweb.conf $HTTP_CONF_DIR/kojiweb.conf
    fi

    mkdir -p /etc/kojiweb/backup
    mv /etc/kojiweb/web.conf /etc/kojiweb/backup/web.conf
    cat $KOJI_SETUP_WEB_DIR/kojiweb.conf | \
        sed -e 's,#KOJI_WEB_NAME#,'${KOJI_WEB_NAME}',g' \
            -e 's,#KOJI_HUB_NAME#,'${KOJI_HUB_NAME}',g' \
            -e 's,#KOJI_WEB_CRT#,'${KOJI_WEB_CRT}',g' \
            -e 's,#KOJI_CA_CERT#,'${KOJI_CA_CERT}',g' \
        > /etc/kojiweb/web.conf
}

! rpm -qa | grep -q koji-hub && \
	install_package || true

[ ! -f /etc/pki/koji/private/kojihub.key ] && \
	create_certification

if ! su - koji -c "psql -c \"select * from users\"" > /dev/null 2>&1; then
        setup_database
        create_koji_account
fi

[ ! -f /etc/httpd/conf.d/backup/ssl.conf ] && \
	setup_server
