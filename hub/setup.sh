#!/bin/bash
set -xe

# Server side packages installation
dnf install -y  httpd \
                mod_ssl \
                postgresql-server \
                mod_wsgi

# Preparation
mkdir -p /etc/pki/koji/{certs,private,confs}

touch /etc/pki/koji/index.txt
echo 01 > /etc/pki/koji/serial

cd /etc/pki/koji/

cat > /etc/pki/koji/koji-ssl.cnf << EOF
HOME                    = .
RANDFILE                = .rand

[ca]
default_ca              = ca_default

[ca_default]
dir                     = .
certs                   = \$dir/certs
crl_dir                 = \$dir/crl
database                = \$dir/index.txt
new_certs_dir           = \$dir/newcerts
certificate             = \$dir/%s_ca_cert.pem
private_key             = \$dir/private/%s_ca_key.pem
serial                  = \$dir/serial
crl                     = \$dir/crl.pem
x509_extensions         = usr_cert
name_opt                = ca_default
cert_opt                = ca_default
default_days            = 3650
default_crl_days        = 30
default_md              = sha256
preserve                = no
policy                  = policy_match

[policy_match]
countryName             = match
stateOrProvinceName     = match
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[req]
default_bits            = 1024
default_keyfile         = privkey.pem
default_md              = sha256
distinguished_name      = req_distinguished_name
attributes              = req_attributes
x509_extensions         = v3_ca                    # The extentions to add to the self signed cert
string_mask             = MASK:0x2002

[req_distinguished_name]
countryName                     = Country Name (2 letter code)
countryName_default             = AT
countryName_min                 = 2
countryName_max                 = 2
stateOrProvinceName             = State or Province Name (full name)
stateOrProvinceName_default     = Vienna
localityName                    = Locality Name (eg, city)
localityName_default            = Vienna
0.organizationName              = Organization Name (eg, company)
0.organizationName_default      = My company
organizationalUnitName          = Organizational Unit Name (eg, section)
commonName                      = Common Name (eg, your name or your server\'s hostname)
commonName_max                  = 64
emailAddress                    = Email Address
emailAddress_max                = 64

[req_attributes]
challengePassword               = A challenge password
challengePassword_min           = 4
challengePassword_max           = 20
unstructuredName                = An optional company name

[usr_cert]
basicConstraints                = CA:FALSE
nsComment                       = "OpenSSL Generated Certificate"
subjectKeyIdentifier            = hash
authorityKeyIdentifier          = keyid,issuer:always
subjectAltName                  = email:move

[v3_ca]
subjectKeyIdentifier            = hash
authorityKeyIdentifier          = keyid:always,issuer:always
basicConstraints                = CA:true
subjectAltName                  = email:move
EOF

# SSL Certification
openssl genrsa -out private/koji_ca_cert.key 2048
openssl req -new -x509 \
-subj "/C=US/ST=Massachusetts/L=Westford/O=RedHat, Inc./OU=PNT/CN=koji-master.local" \
-days 3650 -key private/koji_ca_cert.key -out koji_ca_cert.crt -extensions v3_ca \
-config <(cat koji-ssl.cnf | sed 's/email:move/DNS.1:localhost,DNS.2:koji-master.local,DNS.3:kojihub,email:move/g')

cp private/koji_ca_cert.key private/kojihub.key
cp koji_ca_cert.crt certs/kojihub.crt

# Initial DB
su - postgres -c "PGDATA=/var/lib/pgsql/data initdb"
systemctl enable postgresql
systemctl start postgresql

useradd -G postgres -u 2000 -M -N -d /var/run -s /bin/bash koji
su - postgres -c "createuser --no-superuser --no-createrole --no-createdb koji"
su - postgres -c "createdb -O koji koji"
su - postgres -c "psql -c \"alter user koji with encrypted password 'koji';\""

dnf install -y koji-hub 
su - koji -c "psql koji koji < /usr/share/doc/koji/docs/schema.sql"
