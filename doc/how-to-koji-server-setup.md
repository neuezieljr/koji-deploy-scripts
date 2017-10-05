# How To Setup Koji Server

Koji is the software that builds RPM packages for the Fedora project. This document will explain how to create your own Koji server step by step. The original server setup how to can be found on Koji official site: https://docs.pagure.org/koji/server_howto/

### 1. Server Preparation
 - Server OS: Fedora / CentOS / RedHat Enterprise Linux
 - Recommend packages
   - httpd
   - mod_ssl
   - mod_wsgi
   - postgresql-server
 - Install necessary packages on server (example is base on Fedora 26)
```
(kojihub)$ dnf install httpd \
                       mod_ssl \
                       mod_wsgi \
                       postgresql-server
```
```If you are running on CentOS or RedHat Linux simply change *dnf* to *yum*.```

### 2. Install Koji Hub
 - Install the Koji-hub package
```
(kojihub)$ dnf install koji-hub
```
#### 3. Setup database
 - Database initialization
You need to create a new account (here is koji) to manage the database. After the account is created, use it to create our koji database.
```
(kojihub)$ su - postgres -c "PGDATA=/var/lib/pgsql/data initdb"
(kojihub)$ systemctl start postgresql                                          # don't forget to start database
(kojihub)$ useradd -G postgres -u 2000 -M -N -d /var/run -s /bin/bash koji
(kojihub)$ su - postgres -c "createuser --no-superuser --no-createrole --no-createdb koji"
(kojihub)$ su - postgres -c "createdb -O koji koji"
(kojihub)$ su - postgres -c "psql -c \"alter user koji with encrypted password 'koji';\""
(kojihub)$ su - koji -c "psql koji koji < /usr/share/doc/koji*/docs/schema.sql"
``` 
 - Create roles in database
You have to create an admin roles (here is kojiadmin) in the koji database. You have to run SQL command to create admin account.

```
# add kojiadmin role in DB
(kojihub)$ echo "INSERT INTO users (name, status, usertype) VALUES ('kojiadmin', 0, 0);" | su - koji -c "psql koji koji"
(kojihub)$ export ADMUID=$(echo "select id from users where name = 'kojiadmin'" | su - koji -c "psql koji koji" | tail -3 | head -1)
(kojihub)$ echo "INSERT INTO user_perms (user_id, perm_id, creator_id) VALUES ($ADMUID, 1, $ADMUID);" | su - koji -c "psql koji koji"
```
### 4. Generate SSL certificate
 - Generate koji hub SSL certificate
Prepare OpenSSL certification config file, the openssl.cnf sample can be found on [koji document](https://docs.pagure.org/koji/server_howto/#setting-up-ssl-certificates-for-authentication) or [here](https://github.com/neuezieljr/koji-deploy-scripts/blob/master/hub/openssl.cnf). Create /etc/pki/koji directory in your system and download the config file into the directory.
Using following commands to generate Koji hub certificate.
```
(kojihub)$ mkdir -p /etc/pki/koji/{certs,private,confs}
(kojihub)$ cd /etc/pki/koji
(kojihub)$ touch /etc/pki/koji/index.txt
(kojihub)$ echo 01 > /etc/pki/koji/serial
(kojihub)$ openssl genrsa -out private/koji_ca_cert.key 2048
(kojihub)$ openssl req -new -x509 \
       -days 3650 -key private/koji_ca_cert.key -out koji_ca_cert.crt \
       -extensions v3_ca \
       -subj "/C=US/ST=Massachusetts/L=Boston/O=Company/OU=Department/CN=<your_kojihub_hostname>" \
       -config <(cat openssl.cnf | \
                 sed "s/email:move/DNS.1:localhost,DNS.2:<your_kojihub_hostname>,email:move/g")
(kojihub)$ cp private/koji_ca_cert.key private/kojihub.key
(kojihub)$ cp koji_ca_cert.crt certs/kojihub.crt
```

 - Gerneate kojiadmin SSL certificate
Every role that is used to connect to koji should have their own certificates. You can find the script in [koji certiface section](https://docs.pagure.org/koji/server_howto/#generate-the-koji-component-certificates-and-the-admin-certificate) or use the following scripts to gernerate.
```
#!/bin/bash
# Original reference script: https://docs.pagure.org/koji/server_howto/#generate-the-koji-component-certificates-and-the-admin-certificate
# usage:
#   <script_name> <username>
user=$1
password=$user # change password
caname=koji
user_conf=${user}-ssl.cnf

#generate user private key
openssl genrsa -out private/${user}.key 2048

cp openssl.cnf $user_conf

# You can change the subj string to you want, but remember the CN should be different for each account.
openssl req -config $user_conf -new -nodes -out certs/${user}.csr -key private/${user}.key \
        -subj "/C=US/ST=Massachusetts/L=Boston/O=Company/OU=Department/CN=${user}/emailAddress=${user}@example.com"

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
(kojihub)$ create-user-certificate.sh kojiadmin
...

(kojihub)$ ls -1 /etc/pki/koji/certs/
kojiadmin-crtonly.crt
kojiadmin.crt
kojiadmin.csr
kojiadmin.pem
kojiadmin_browser_cert.p12
```
#### 5. Koji Hub Configuration
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
 Modify /etc/httpd/conf.d/kojihub.conf, uncomment below liens
```
<Location /kojihub/ssllogin>
    SSLVerifyClient require
    SSLVerifyDepth  10
    SSLOptions +StdEnvVars
</Location>
```

 - Add SSL subject string to /etc/koji-hub/hub.conf
In order to use SSL auth, these settings need to be valid and inline with other services configurations for kojiweb to allow logins.
```
(kojihub)$ cat /etc/pki/koji/index.txt
V	271003042626Z		01	unknown	/C=US/ST=Massachusetts/O=Company/OU=Department/CN=kojiadmin
```
Add above line to  /etc/koji-hub/hub.conf
```
DNUsernameComponent = CN
ProxyDNs = /C=US/ST=Massachusetts/O=Company/OU=Department/CN=kojiadmin
```
```Note, there are some options in hub.conf might need to be changed, e.g. KojiWebURL.```

 - Start the HTTP service
Now it is time to apply new settings on HTTP servce, you will need to restart httpd service.
```
(kojihub)$ systemctl restart httpd
```

 - Enable http/https service on your host.
Fedora/CentOS/RedHat Linux enable firewall by default, and http/https servers are not allowed in the begining. You need to enable HTTP/HTTPS ports to accept connections.
```
(kojihub)$ firewall-cmd --allow-service=http              # enable http service in current session
(kojihub)$ firewall-cmd --allow-service=http --permanent  # enable http service all the time
(kojihub)$ firewall-cmd --allow-service=https             # enable https service in current session
(kojihub)$ firewall-cmd --allow-service=https --permanent # enable https service all the time
```

Koji hub is now ready for response, let's create a config file and use it to connect koji hub.
```
# modify the tag <your_kojihub_hostname>, and save the file to $HOME/.koji/config
[koji]
server = https://<your_kojihub_hostname>/kojihub
authtype = ssl
cert = /etc/pki/koji/certs/kojiadmin.crt
ca = /etc/pki/koji/koji_ca_cert.crt 
serverca = /etc/pki/koji/koji_ca_cert.crt
weburl = https://<your_kojihub_hostname>/koji
topurl = https://<your_kojihub_hostname>/kojifiles
```
Run hello command to koji and see if it can response.
```
 # if the config file is in ~/.koji , you don't have to specify it.
 # if it is not in ~/.koji, you have to use -c to specify it.
(kojihub)$ koji hello
olá, kojiadmin!

You are using the hub at https://localhost/kojihub
Authenticated via client certificate /etc/pki/koji/certs/kojiadmin.crt
```

If hello message is generated, that means the koji hub is ready to work. Next we are goning to setup kojiweb service.

#### 5. Setup Koji Web
Koji Web is a web service that allows you to monitor koji status.

 - Install necessary packages
   - koji-web
```
(kojiweb)$ dnf install koji-web
```

 - Create a role for koji web in database
In order to perfrom management on koji web, you have to create an admin account for koji web.
```
# add kojiweb role in DB
(kojihub)$ echo "INSERT INTO users (name, status, usertype) VALUES ('kojiweb', 0, 0);" | su - koji -c "psql koji koji"
(kojihub)$ export WEBUID=$(echo "select id from users where name = 'kojiweb'" | su - koji -c "psql koji koji" | tail -3 | head -1)
(kojihub)$ echo "INSERT INTO user_perms (user_id, perm_id, creator_id) VALUES ($WEBUID, 1, $WEBUID);" | su - koji -c "psql koji koji"
```

 - Create kojiweb Certificate
Just like kojiadmin, you will need to create certificate for kojiweb account. Run the previous script to create certificates.
```
# Use the script we created before to generate certs for kojiweb.
(kojihub)$ create-user-certificate.sh kojiweb
```

 - Enable SSL login in koji web configuration
Modify /etc/httpd/conf.d/kojiweb, uncomment below lines to enable SSL login feature.
```
<Location /koji/login>
    SSLVerifyClient require
    SSLVerifyDepth  10
    SSLOptions +StdEnvVars
</Location>
```

 - Set SSL certificate files' path in koji web conf
Modify /etc/kojiweb/web.conf, add below lines. Make sure all crt files' path is correct on your host.
```
# SSL authentication options
WebCert = /etc/pki/koji/certs/kojiweb.crt
ClientCA = /etc/pki/koji/koji_ca_cert.crt
KojiHubCA = /etc/pki/koji/koji_ca_cert.crt
```
```Note, there are some options in web.conf might need to be changed, e.g. KojiHubURL, KojiFilesURL.```

 - Restart HTTP again to start koji web
```
(kojiweb)$ systemctl restart httpd
```

Finally, use your browser and open ```https://<your_kojiweb_hostname>```. You should be able see koji web is running like [fedora koji site](https://koji.fedoraproject.org/koji/)

#### 6. Setup Builder
The last step is to create a builder to run koji tasks.
 - Install necessary packages:
   - koji-builder
   - mock
   - rpm-build
   - createrepo
   - If you want to run image build on this builder, these packages are necessary:
     - livecd-tools
     - python-kickstart
     - pycdio
```
(kojbuilder)$ dnf install  mock \
                           rpm-build \
                           createrepo \
                           livecd-tools \
                           python-kickstart \
                           pycdio \
                           koji-builder
```

 - Create SSL certificate on the hub for kojibuilder
```
# Use the script we created before to generate certs for kojibuilder.
(kojihub)$ create-user-certificate.sh kojibuilder
```

 - Copy certificate file to your kojibuilder:/etc/kojid/
```
copy <kojihub>/etc/pki/koji/certs/kojibuilder.crt to <kojibuilder>/etc/kojid/kojibuilder.crt
copy <kojihub>/etc/pki/koji/koji_ca_cert.crt to <kojibuilder>/etc/kojid/serverca.crt
```

 - Add builder on kojihub and the channels as well
```
(kojihub)$ koji add-host kojibuilder "x86_64"
(kojihub)$ koji add-host-to-channel createrepo kojibuilder
(kojihub)$ koji add-host-to-channel livecd kojibuilder
```

 - Modify kojid.conf in builder side
You need to specify necessary certificate files in /etc/kojid/kojid.conf
```
;client certificate
cert = /etc/kojid/kojibuilder.crt

;certificate of the CA that issued the HTTP server certificate
serverca = /etc/kojid/serverca.crt
```
```Note, there are some options in kojid.conf might need to be changed, e.g. server, topurl.```

 - Start kojid
Start kojid service on your builder
```
(kojibuilder)$ systemctl start kojid
```

If kojid is started successfully, you should be able to see the builder is ready on the hosts list.
```
(kojihub)$ koji list-hosts
Hostname                     Enb Rdy Load/Cap Arches           Last Update
kojibuilder                  Y   Y    0.0/2.0 x86_64           2017-10-05 15:25:23
```
