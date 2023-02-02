#!/bin/bash

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

bkp_dir_local='/backup/mysql_backup/'
bkp_dir_remote='/mnt/nas/mysql/'
bkp_log_file='/var/log/mysql_backup.log'
bkp_file_regex='db_*.gz'
bkp_sql_host='db-server.local'
bkp_storage_host='nas-server.local'
bkp_purge_period=90

# Get backup user credentials
source /root/mysql-backup.auth
backupuser=$(eval echo ${backupuser} | base64 --decode)
secret=$(eval echo ${secret} | base64 --decode)

# Define and count databases for backup and do backup in a loop
declare -a dbname=($(/usr/bin/mysql -h $bkp_sql_host -u $backupuser -p$secret --batch -e "show databases;" | tail -n +2))
dbcount=${#dbname[@]}
echo "$(date +"%Y-%m-%d %T") Info: $dbcount databases will be backuped." >> $bkp_log_file

for i in "${dbname[@]}"
do
        echo "$(date +"%Y-%m-%d %T") Start backup of db $i." >> $bkp_log_file
        /usr/bin/mysqldump -h $bkp_sql_host --single-transaction -u $backupuser -p$secret $i | gzip -9 -c > $bkp_dir_local/db_"$i"_`date +%F`.sql.gz
        echo "$(date +"%Y-%m-%d %T") End backup of db $i." >> $bkp_log_file
done

# Mount NFS share to move backups out of server
/bin/mount -t nfs -o rw,noatime,nolock,hard,intr,tcp,timeo=15,retry=0 $bkp_storage_host:/mnt/nfs_backup /mnt/nas/

# NFS share availability
if [[ -z "$(cat /proc/mount | grep $bkp_storage_host)" ]]
then {
     echo "$(date +"%Y-%m-%d %T") NFS share mount error."
     exit
     }
fi

# Move all backups to NFS share except recent
find $bkp_dir_local -type f -name "$bkp_file_regex" -mtime +1 -exec mv {} $bkp_dir_remote \; >> $bkp_log_file

# Count backups on remote share and calculate minimum number of backups at remote storage
archcount="$(ls -l $bkp_dir_remote | wc -l)"
archlimit=$((dbcount * bkp_purge_period))

if [[ $archcount -gt $archlimit ]]
        then
        echo "$(date +"%Y-%m-%d %T") INFO: found $arcount files in remote backup directory (bkp_dir_remote). Purging old." >> $bkp_log_file
        find $bkp_dir_remote -type f -name "$bkp_file_regex" -mtime +"$bkp_purge_period" -delete \; >> $bkp_log_file
fi
