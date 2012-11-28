# ib_csm_csv.sh - test for xtrabackup
# Copyright (C) 2009-2011 Percona Inc.

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
. inc/common.sh

init
run_mysqld --innodb_file_per_table
run_cmd ${MYSQL} ${MYSQL_ARGS} -e "create database csv"
run_cmd ${MYSQL} ${MYSQL_ARGS} -e "create table csm (a int NOT NULL ) ENGINE=CSV" csv
# Adding initial rows
vlog "Adding initial rows to database..."
numrow=100
count=0
while [ "$numrow" -gt "$count" ]
do
	${MYSQL} ${MYSQL_ARGS} -e "insert into csm values ($count);" csv
	let "count=count+1"
done
vlog "Initial rows added"

# Full backup
# backup root directory
mkdir -p $topdir/backup

vlog "Starting backup"
run_cmd ${IB_BIN} --user=root --socket=$mysql_socket $topdir/backup > $OUTFILE 2>&1 
full_backup_dir=`grep "innobackupex: Backup created in directory" $OUTFILE | awk -F\' '{print $2}'`
vlog "Full backup done to directory $full_backup_dir"

# Saving the checksum of original table
checksum_a=`${MYSQL} ${MYSQL_ARGS} -Ns -e "checksum table csm;" csv | awk '{print $2}'`
vlog "Table checksum is $checksum_a"

vlog "Preparing backup"
# Prepare backup
echo "###########" >> $OUTFILE
echo "# PREPARE #" >> $OUTFILE
echo "###########" >> $OUTFILE
run_cmd ${IB_BIN} --apply-log $full_backup_dir >> $OUTFILE 2>&1 
vlog "Data prepared for restore"

# Destroying mysql data
stop_mysqld
rm -rf $mysql_datadir/*
vlog "Data destroyed"

# Restore backup
vlog "Copying files"
echo "###########" >> $OUTFILE
echo "# RESTORE #" >> $OUTFILE
echo "###########" >> $OUTFILE
run_cmd ${IB_BIN} --copy-back $full_backup_dir >> $OUTFILE 2>&1
vlog "Data restored"

run_mysqld --innodb_file_per_table
vlog "Checking checksums"
checksum_b=`${MYSQL} ${MYSQL_ARGS} -Ns -e "checksum table csm" incremental_sample | awk '{print $2}'`

if [ $checksum_a -ne $checksum_b  ]
then 
	vlog "Checksums are not equal"
	exit -1
fi
vlog "Checksums are OK"
stop_mysqld
clean
