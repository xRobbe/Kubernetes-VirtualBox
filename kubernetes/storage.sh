dd if=/dev/zero of=/var/srv/gitbucket/mariadb.xfs bs=512 count=4194304
mkfs -t xfs /var/srv/gitbucket/mariadb.xfs
echo "/var/srv/gitbucket/mariadb.xfs /var/srv/gitbucket/mariadb xfs defaults 0 0" >> /etc/fstab
mount -a