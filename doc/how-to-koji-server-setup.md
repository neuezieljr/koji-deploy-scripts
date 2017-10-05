# How To Setup Koji Server

Koji is the software that builds RPM packages for the Fedora project. The is document will explain how to create you own Koji server step by step. The original server setup how to can be found on Koji official site: https://docs.pagure.org/koji/server_howto/

### 1. Server Preparation
 - Server OS: Fedora / CentOS / RedHat Enterprise Linux
 - Recommend packages
   - avahi
   - nss-mdns
   - httpd
   - mod_ssl
   - mod_wsgi
   - postgresql-server
 - If you are running on Fedora
```
% dnf install avahi \
              nss-mdns \
              httpd \
              mod_ssl \
              mod_wsgi \
              postgresql-server
```

 - If you are running on CentOS or RedHat Linux simply change *dnf* to *yum*.

### 2. Install Koji Hub
  - Install the Koji-hub package
```
% dnf install koji-hub
```
  - Generate SSL certification
Prepare OpenSSL certification config file, the openssl.cnf sample can be found from [here](https://github.com/neuezieljr/koji-deploy-scripts/blob/master/hub/openssl.cnf). Create /etc/pki/koji directory in your system and download the config file to the directory.

  - Create the root CA for koji-hub
```
% cd /etc/pki/koji
% mkdir {certs,private,confs}
% touch /etc/pki/koji/index.txt
% echo 01 > /etc/pki/koji/serial
% openssl genrsa -out private/koji_ca_cert.key 2048
% openssl req -new -x509 \
       -days 3650 -key private/koji_ca_cert.key -out koji_ca_cert.crt \
       -extensions v3_ca \
       -subj "/C=US/ST=Massachusetts/L=Boston/O=Company/OU=Department/CN=<your_hostname>" \
       -config <(cat openssl.cnf | \
                 sed "s/email:move/DNS.1:localhost,DNS.2:<your_hostname>,email:move/g")
cp private/koji_ca_cert.key private/kojihub.key
cp koji_ca_cert.crt certs/kojihub.crt
```

- Setup database
```
% su - postgres -c "PGDATA=/var/lib/pgsql/data initdb"
% systemctl start postgresql         # start database
% useradd -G postgres -u 2000 -M -N -d /var/run -s /bin/bash koji
% su - postgres -c "createuser --no-superuser --no-createrole --no-createdb koji"
% su - postgres -c "createdb -O koji koji"
% su - postgres -c "psql -c \"alter user koji with encrypted password 'koji';\""
% su - koji -c "psql koji koji < /usr/share/doc/koji*/docs/schema.sql"
``` 
 - Create roles in database
 We have to create several an admin roles to on koji hub:
	- kojiadmin : Administrator

```
# add kojiadmin role in DB
% echo "INSERT INTO users (name, status, usertype) VALUES ('kojiadmin', 0, 0);" | su - koji -c "psql koji koji"
% export ADMUID=$(echo "select id from users where name = 'kojiadmin'" | su - koji -c "psql koji koji" | tail -3 | head -1)
% echo "INSERT INTO user_perms (user_id, perm_id, creator_id) VALUES ($ADMUID, 1, $ADMUID);" | su - koji -c "psql koji koji"
```
 - Generate certificate for kojiadmin
Above script can help us generate user certificate easily.
```
#!/bin/bash
# usage:
#   <script_name> <username>
user=$1
password=$user # change password
caname=koji
user_conf=${user}-ssl.cnf

#generate user private key
openssl genrsa -out private/${user}.key 2048

cp openssl.cnf $user_conf

openssl req -config $user_conf -new -nodes -out certs/${user}.csr -key private/${user}.key \
        -subj "/C=US/ST=Massachusetts/L=Boston/O=Company/OU=Department/CN=${user}/emailAddress=${user}@<your_hostname>"

openssl ca -config $user_conf -batch -keyfile private/${caname}_ca_cert.key -cert ${caname}_ca_cert.crt \
        -out certs/${user}-crtonly.crt -outdir certs -infiles certs/${user}.csr

openssl pkcs12 -export -inkey private/${user}.key -passout "pass:${password}" \
               -in certs/${user}-crtonly.crt -certfile ${caname}_ca_cert.crt \
               -CAfile ${caname}_ca_cert.crt -chain -clcerts \
               -out certs/${user}_browser_cert.p12

openssl pkcs12 -clcerts -passin "pass:${password}" -passout "pass:${password}" \
               -in certs/${user}_browser_cert.p12 -inkey private/${user}.key \
               -out certs/${user}.pem

cat certs/${user}-crtonly.crt private/${user}.key > certs/${user}.crt
```
```
# Create cert for kojiadmin, files are created in /etc/pki/koji/certs/
% create-user-certificate.sh kojiadmin
...

% ls -1 /etc/pki/koji/certs/
kojiadmin-crtonly.crt
kojiadmin.crt
kojiadmin.csr
kojiadmin.pem
kojiadmin_browser_cert.p12
```
  - Enable SSL on HTTP server
Modify /etc/httpd/conf.d/ssl.conf, add above lines
```
SSLCertificateFile /etc/pki/koji/certs/kojihub.crt
SSLCertificateKeyFile /etc/pki/koji/private/kojihub.key
SSLCertificateChainFile /etc/pki/koji/koji_ca_cert.crt
SSLCACertificateFile /etc/pki/koji/koji_ca_cert.crt
SSLVerifyDepth  10
```

   - Enable SSL Authentication on Kojihub
 Modify /etc/httpd/conf.d/kojihub.conf, uncomment above liens
```
<Location /kojihub/ssllogin>
    SSLVerifyClient require
    SSLVerifyDepth  10
    SSLOptions +StdEnvVars
</Location>
```

  - Enable SSL on Kojihub configuration
In order to use SSL auth, these settings need to be valid and inline with other services configurations for kojiweb to allow logins.
```
% cat /etc/pki/koji/index.txt
V	271003042626Z		01	unknown	/C=US/ST=Massachusetts/O=Company/OU=Department/CN=kojiadmin
```

According to your setting, add above lines in /etc/koji-hub/hub.conf

```
DNUsernameComponent = CN
ProxyDNs = /C=US/ST=Massachusetts/O=Company/OU=Department/CN=kojiadmin
```

Koji hub is now ready for response, let's create a config file to connect to our hub.
```
# save the file to $HOME/.koji/config
[koji]
server = https://localhost/kojihub
authtype = ssl
cert = /etc/pki/koji/certs/kojiadmin.crt
ca = /etc/pki/koji/koji_ca_cert.crt 
serverca = /etc/pki/koji/koji_ca_cert.crt
weburl = https://localhost/koji
topurl = https://localhost/kojifiles
```
Run hello command to koji and see if it can response.
```
$ koji -c ~/.koji/config hello
olá, kojiadmin!

You are using the hub at https://localhost/kojihub
Authenticated via client certificate /etc/pki/koji/certs/kojiadmin.crt
```

If you can see the hello message, that means koji hub is ready to work. Next let's setup our kojiweb interface.
 

