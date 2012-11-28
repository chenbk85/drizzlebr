# xb_export.sh - test for xtrabackup
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

if [ "$MYSQL_VERSION" != "percona" ]; then
  exit $SKIPPED_EXIT_CODE
fi

backup_dir=$topdir/xb_export_backup
rm -rf $backup_dir
mkdir $backup_dir
# Starting database server
run_mysqld --innodb_file_per_table --innodb_file_format=Barracuda

# Loading table schema
load_dbase_schema incremental_sample

# Adding some data to database
vlog "Adding initial rows to database..."
numrow=100
count=0
while [ "$numrow" -gt "$count" ]
do
	${MYSQL} ${MYSQL_ARGS} -e "insert into test values ($count, $numrow);" incremental_sample
	let "count=count+1"
done
vlog "Initial rows added"

checksum_1=`${MYSQL} ${MYSQL_ARGS} -Ns -e "checksum table test" incremental_sample | awk '{print $2}'`
rowsnum_1=`${MYSQL} ${MYSQL_ARGS} -Ns -e "select count(*) from test" incremental_sample`
vlog "rowsnum_1 is $rowsnum_1"
vlog "checksum_1 is $checksum_1"

# Performing table backup
run_cmd xtrabackup --no-defaults --datadir=$mysql_datadir --backup --target-dir=$backup_dir
vlog "Table was backed up"

vlog "Re-initializing database server"
stop_mysqld
# Can't use clean/init because that will remove $backup_dir as well
clean_datadir
run_mysqld --innodb_file_per_table --innodb_expand_import=1 --innodb_file_format=Barracuda
load_dbase_schema incremental_sample
vlog "Database was re-initialized"

run_cmd ${MYSQL} ${MYSQL_ARGS} -e "alter table test discard tablespace;" incremental_sample
run_cmd xtrabackup --no-defaults --datadir=$mysql_datadir --prepare --export --target-dir=$backup_dir
run_cmd cp $backup_dir/incremental_sample/test* $mysql_datadir/incremental_sample/
run_cmd ls -lah $mysql_datadir/incremental_sample/
run_cmd ${MYSQL} ${MYSQL_ARGS} -e "alter table test import tablespace" incremental_sample
vlog "Table has been imported"

vlog "Cheking checksums"
checksum_2=`${MYSQL} ${MYSQL_ARGS} -Ns -e "checksum table test;" incremental_sample | awk '{print $2}'`
vlog "checksum_2 is $checksum_2"
rowsnum_1=`${MYSQL} ${MYSQL_ARGS} -Ns -e "select count(*) from test" incremental_sample`
vlog "rowsnum_1 is $rowsnum_1"

if [ $checksum_1 -ne $checksum_2  ]
then 
	vlog "Checksums are not equal"
	exit -1
fi

vlog "Checksums are OK"

# Some testing queries
run_cmd ${MYSQL} ${MYSQL_ARGS} -e "select count(*) from test;" incremental_sample
run_cmd ${MYSQL} ${MYSQL_ARGS} -e "show create table test;" incremental_sample

# Performing full backup of imported table
mkdir -p $topdir/backup/full

xtrabackup --no-defaults --datadir=$mysql_datadir --backup --target-dir=$topdir/backup/full
xtrabackup --no-defaults --datadir=$mysql_datadir --prepare --apply-log-only --target-dir=$topdir/backup/full
xtrabackup --no-defaults --datadir=$mysql_datadir --prepare --target-dir=$topdir/backup/full

run_cmd ${MYSQL} ${MYSQL_ARGS} -e "delete from test;" incremental_sample

stop_mysqld

cd $topdir/backup/full
cp -r * $mysql_datadir
cd -

run_mysqld --innodb_file_per_table

vlog "Cheking checksums"
checksum_3=`${MYSQL} ${MYSQL_ARGS} -Ns -e "checksum table test;" incremental_sample | awk '{print $2}'`
vlog "checksum_3 is $checksum_3"

if [ $checksum_3 -ne $checksum_2  ]
then
        vlog "Checksums are not equal"
        exit -1
fi

vlog "Checksums are OK"

rm -rf $backup_dir
stop_mysqld
clean
