#!/bin/bash

VER=0
echo "What version do you want to install?"
echo "1) 4.0 LTS"
echo "2) 5.0 LTS"

read -p "Please, select number 1 or 2 : " yn

case "$yn" in
    1) echo "Do you want to install 4.0 LTS?";
     VER=1;
     ;;
    2) echo "Do you want to install 5.0 LTS?";
     VER=2;
     ;;
   *) echo "Abort the installation.";
     exit ;;
esac
read -p "Hit enter: "
echo "VER="$VER

if [ "$VER" == "1" ];then
    rpm -Uvh https://repo.zabbix.com/zabbix/4.0/rhel/8/x86_64/zabbix-release-4.0-2.el8.noarch.rpm
elif [ "$VER" == "2" ];then
    rpm -Uvh https://repo.zabbix.com/zabbix/5.0/rhel/8/x86_64/zabbix-release-5.0-1.el8.noarch.rpm
else
    echo "Abort the installation."
    exit;
fi

setenforce 0
systemctl stop firewalld
systemctl disable firewalld

if [ -e "/etc/selinux/config" ];then
    sed -i -e "s/SELINUX=enforcing/SELINUX=disabled/" /etc/selinux/config
fi

dnf clean all

dnf install -y mariadb-server.x86_64 httpd

if [ "$VER" == "1" ];then
    dnf install -y zabbix-server-mysql zabbix-web-mysql zabbix-agent
elif [ "$VER" == "2" ];then
    dnf install -y zabbix-server-mysql zabbix-web-mysql zabbix-apache-conf zabbix-agent
fi

sed -i -e "s/\[mariadb\]/\[mariadb\]\ninnodb-strict-mode=0/" /etc/my.cnf.d/mariadb-server.cnf

systemctl start mariadb

DB=mysql
PASSWORD="Parkzabbix"

SQL=`cat << EOS
use $DB
create database zabbix character set utf8 collate utf8_bin;
grant all privileges on zabbix.* to zabbix@localhost identified by '${PASSWORD}';

EOS`

echo "$SQL" | mysql -u root

zcat `find  /usr/share/doc/zabbix-server-mysql* |  grep create.sql.gz` | mysql -uzabbix -p${PASSWORD} zabbix

echo "php_value[date.timezone] = "`timedatectl | grep "Time zone" | awk '{print $3}'` >> /etc/php-fpm.d/zabbix.conf

sed -i -e "s/# DBPassword=/DBPassword=${PASSWORD}/" /etc/zabbix/zabbix_server.conf

TEXT="
<?php \n\
// Zabbix GUI configuration file. \n\
global \$DB; \n\
\n\
\$DB['TYPE']     = 'MYSQL'; \n\
\$DB['SERVER']   = 'localhost'; \n\
\$DB['PORT']     = '0'; \n\
\$DB['DATABASE'] = 'zabbix'; \n\
\$DB['USER']     = 'zabbix'; \n\
\$DB['PASSWORD'] = '${PASSWORD}'; \n\
 \n\
// Schema name. Used for PostgreSQL. \n\
\$DB['SCHEMA'] = ''; \n\
 \n\
\$ZBX_SERVER      = 'localhost'; \n\
\$ZBX_SERVER_PORT = '10051'; \n\
\$ZBX_SERVER_NAME = 'park1'; \n\
\n\
\$IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG; "

echo -e $TEXT > /etc/zabbix/web/zabbix.conf.php
chmod 644 /etc/zabbix/web/zabbix.conf.php

systemctl restart zabbix-server httpd php-fpm
systemctl enable zabbix-server httpd php-fpm mariadb

echo "Zabbix Install Completed."
echo "Product by Park.iggy<naiggy@gmail.com>"