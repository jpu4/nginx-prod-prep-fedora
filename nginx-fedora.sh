#!/bin/bash

# Credit for initial lineup:
# https://www.howtoforge.com/how-to-install-nginx-with-php-and-mariadb-lemp-stack-on-fedora-32/

hostnamectl set-hostname f33-lemp

dnf upgrade -y
dnf install -y wget curl nano vim fish

fedoraVersion="33"
dirWeb="/var/www"
dirConf="$dirWeb/conf"
dirBak="$dirWeb/bak"
dirSites="$dirWeb/sites"
dirLogs="$dirWeb/logs"
dirScripts="$dirWeb/scripts"
configNginx="/etc/nginx/nginx.conf"
configFPM="/etc/php-fpm.d/www.conf"
configOpcache="/etc/php.d/10-opcache.ini"
configPHPini="/etc/php.ini"

cd ~/
ln -s $dirWeb

dbadmin=""
dbadminpass=""

# need to find away around this:
# https://docs.nextcloud.com/server/20/admin_manual/installation/selinux_configuration.html
setenforce 0

# FIREWALL
firewall-cmd --state
firewall-cmd --set-default-zone=public
firewall-cmd --zone=public --permanent --add-service=http
firewall-cmd --zone=public --permanent --add-service=https
firewall-cmd --zone=public --permanent --list-services
systemctl reload firewalld

# PHP
dnf -y install https://rpms.remirepo.net/fedora/remi-release-$fedoraVersion.rpm
dnf config-manager --set-enabled remi
dnf config-manager --set-disabled remi-modular
dnf install -y php-cli php-fpm php-mysqlnd php-process php-zlib php-libxml
dnf install -y php-posix php-zip php-dom php-xmlwriter php-xmlreader php-bz2
dnf install -y php-mbstring php-gd php-simplexml php-mysql php-fileinfo
dnf install -y php-ctype php-curl php-iconv php-json php-libxml php-openssl
dnf install -y php-intl php-ldap php-smbclient php-ftp php-imap php-bcmath
dnf install -y php-redis php-memcached php-imagick php-pcntl php-gmp exif
php --version

sed -i -e "s|memory_limit = 128M|memory_limit = 512M|g" $configPHPini
sed -i -e "s|upload_max_filesize = 2M|upload_max_filesize = 32M|g" $configPHPini
sed -i -e "s|post_max_size = 2M|upload_max_filesize = 32M|g" $configPHPini

# MYSQL
dnf install mariadb-server -y
mysql --version
systemctl enable mariadb
systemctl start mariadb
# mysql_secure_installation # If you're monitoring the install

# REDIS
dnf install redis php-redis -y
systemctl enable --now redis

# nano /etc/redis.conf

# If you want remote clients to connect to your Redis instance then find the line bind 127.0.0.1 and change it to the following.
# bind 0.0.0.0

# You can also change the default port on which Redis listens to from 6379 to a value of your choice.
# port 3458

# To configure Redis as a cache server, set the following values as given.
# maxmemory 256mb
# maxmemory-policy allkeys-lru
# This tells Redis to remove any key using the LRU algorithm when the maximum memory of 256MB is reached. You can set the memory value as per your requirement and the server you are using.

# You can set a password so that any client which needs Redis will be required to authenticate first. To do that set a password using the following directive.
# requirepass  <AuthPassword>

systemctl restart redis

firewall-cmd --zone=public --permanent --add-port=6379/tcp
firewall-cmd --reload

# NGINX
dnf install nginx -y
nginx -v
systemctl start nginx
systemctl enable nginx

# include $dirconf/*.conf;
# server_names_hash_bucket_size 64;
# types_hash_max_size 4096; <- ignore, already in the file
sed -i -e "s|include /etc/nginx/conf.d/\*.conf;|include /etc/nginx/conf.d/\*.conf;\n include $dirWeb/conf/\*.conf;\n server_names_hash_bucket_size 64;|g" $configNginx
sed -i "s|/usr/share/nginx/html|$dirSites/default/www|" $configNginx

# nano $configNginx

systemctl reload nginx

# PHP-FPM
sed -i "s|user = apache|user = nginx|" $configFPM
sed -i "s|group = apache|group = nginx|" $configFPM
sed -i "s|;clear_env = no|clear_env = no|" $configFPM

systemctl restart php-fpm

# OPCACHE
dnf install php-opcache -y
php -v

# opcache.enable_cli=1
# opcache.enable=1
# opcache.interned_strings_buffer=8
# opcache.max_accelerated_files=10000
# opcache.memory_consumption=128
# opcache.save_comments=1
# opcache.revalidate_freq=1
sed -i "s|;opcache.save_comments=1|opcache.save_comments=1|" $configOpcache
sed -i "s|;opcache.memory_consumption|opcache.memory_consumption|" $configOpcache
sed -i "s|;opcache.interned_strings_buffer|opcache.interned_strings_buffer|" $configOpcache
sed -i "s|;opcache.max_accelerated_files=10000|opcache.max_accelerated_files=10000|" $configOpcache
sed -i "s|;opcache.revalidate_freq=2|opcache.revalidate_freq=1|" $configOpcache

# Login Loop Fix
setfacl -R -m u:nginx:rwx /var/lib/php/opcache/
setfacl -R -m u:nginx:rwx /var/lib/php/session/
setfacl -R -m u:nginx:rwx /var/lib/php/wsdlcache/

# chown -R root:nginx /var/lib/php/opcache/
# chown -R root:nginx /var/lib/php/session/
# chown -R root:nginx /var/lib/php/wsdlcache/
chmod -R 770 /var/lib/php/

systemctl reload nginx

# LET'S ENCRYPT
dnf install certbot-nginx -y
# certbot --nginx --redirect --agree-tos --no-eff-email -d DOMAIN -m ADMINEMAIL
# 25 2 * * * /usr/bin/certbot renew --quiet

# WWW LOCATION
rm -rf $dirWeb/html/
rm -rf $dirWeb/cgi-bin/

mkdir -p $dirBak
mkdir -p $dirConf
mkdir -p $dirLogs
mkdir -p $dirScripts
mkdir -p $dirSites
mkdir -p $dirSites/default/conf
mkdir -p $dirSites/default/db
mkdir -p $dirSites/default/www

touch $dirSites/default/www/t.php
echo "<?php phpinfo(); ?>" > $dirSites/default/www/t.php

mysql -e "CREATE USER '$dbadmin'@'%' IDENTIFIED BY '$dbadminpass';"
mysql -e "GRANT ALL PRIVILEGES ON *.* TO '$dbadmin'@'%' WITH GRANT OPTION;"

echo "
server {
    listen 80;
    listen [::]:80;
    server_name SITEDOMAIN;
    root $dirSites/SITENAME/SITEROOT;

    access_log $dirWeb/logs/SITENAME_access_log;
	error_log $dirWeb/logs/SITENAME_error_log;

    location / {
		try_files   \$uri \$uri/ =404;
	}

    # Load configuration files for the default server block.
    include /etc/nginx/default.d/*.conf;
}
" > $dirConf/nginx-conf-template

# NEXTCLOUD
cd $dirBak
wget https://download.nextcloud.com/server/installer/setup-nextcloud.php
wget https://download.nextcloud.com/server/releases/nextcloud-20.0.2.zip

# WP CLI
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
php wp-cli.phar --info
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp

chown -R nginx: $dirSites/