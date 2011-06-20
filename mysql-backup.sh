#!/bin/bash

print_help()
{
cat <<EOF

MySQL database management — clean, import and export data

Link     http://code.google.com/p/mysql-backup/
License  http://creativecommons.org/licenses/by-sa/3.0/
Author   Nasibullin Rinat
Version  $version

Purpose

  * Command-line utility to create a hot backup of databases
    with the possibility of subsequent recovery.
  * The script is a high-level wrapper for a mysqldump and mysql programs.

Features and advantages

  * Export-Import works at 20-35% faster than using a single
    large *. sql file that combines the structure and data.
  * Data of tables are stored in *. txt files (tabular format, binary charset).
    The file names match the names of the tables.
  * Description of tables stored in two *. sql files (UTF8 charset).
    dump1.sql — tables structure, functions and procedures; dump1.sql — triggers.
  * Export InnoDB tables is performed in a single transaction.
    This ensures data integrity and does not lock the database during export.

EOF
}

print_default()
{
cat <<EOF

Usage: $progname export|import|clear <database> [options]

Options
  -h | --help           More information
  -H | --host           Host, by default "localhost"
  -P | --port           Port, by default "3306"
  -u | --user           User, by default "root"
  -p | --password       Password
  -i | --ignore-tables  List of tables to be ignored when you export data (separated by commas, no spaces)
  -d | --dump-dir       Folder to store data, by default "./dump"
  -b | --bin-dir        Folder where the executable files (mysql, mysqldump), by default "/usr/bin"

Example
  $ ./$progname clear my_database

EOF
}

run_export()
{
	echo "Exporting database \"$database\"…"

	#DB tables, which should be ignored during export
	if [ ${#ignore_tables} -gt 0 ]
	then
		ignore_tables=",$ignore_tables"
		ignore_tables=${ignore_tables//,/ --ignore-table=$database.}
	fi

	echo "Step 1. Creating folder \"$dump_dir\" (if necessary), deleting old files"
	mkdir --mode=777 --parents $dump_dir && rm -f $dump_dir/*.txt && rm -f $dump_dir/*.sql

	echo "Step 2. Creating \"$dump_dir/dump1.sql\" (tables structure, functions and procedures)"
	$bin_dir/mysqldump --user=$user --password=$password --host=$host --port=$port --quick --single-transaction --routines --skip-triggers --hex-blob --no-data $ignore_tables $database | sed -e 's/\/\*\![0-9][0-9]* *DEFINER[^\*]*\*\///g' > $dump_dir/dump1.sql

	echo "Step 3. Creating \"$dump_dir/dump2.sql\" (triggers)"
	#Triggers should not work on import!
	$bin_dir/mysqldump --user=$user --password=$password --host=$host --port=$port --quick --single-transaction --triggers --hex-blob --no-data --skip-add-drop-table --no-create-info $database | sed -e 's/\/\*\![0-9][0-9]* *DEFINER[^\*]*\*\///g' > $dump_dir/dump2.sql

	echo "Step 4. Creating \"$dump_dir/*.txt\" (tables data)"
	#privilege FILE required
	#Column values are dumped using the binary character set and the --default-character-set option is ignored.
	#In effect, there is no character set conversion. If a table contains columns in several character sets, the output data file will as well and you may not be able to reload the file correctly.
	$bin_dir/mysqldump --user=$user --password=$password --host=$host --port=$port --quick --single-transaction --skip-add-drop-table --no-create-info --tab=$dump_dir --verbose $ignore_tables $database > /dev/null

	echo "Done!"
}

run_clear()
{
	echo "Cleaning database \"$database\"…"

	echo "Step 1. Creating folder \"$dump_dir\", if necessary"
	mkdir --mode=777 --parents $dump_dir && rm -f $dump_dir/clear_db.sql

	echo "Step 2. Prepare deleting views"
	$bin_dir/mysql --user=$user --password=$password --host=$host --port=$port --silent --skip-column-names $database --execute "SELECT table_name FROM information_schema.tables WHERE table_schema = '$database' AND table_type = 'VIEW'" | gawk '{print "DROP VIEW IF EXISTS `" $1 "`;"}' >> $dump_dir/clear_db.sql

	echo "Step 3. Prepare deleting tables"
	$bin_dir/mysql --user=$user --password=$password --host=$host --port=$port --silent --skip-column-names $database --execute "SELECT table_name FROM information_schema.tables WHERE table_schema = '$database' AND table_type = 'BASE TABLE'" | gawk '{print "SET FOREIGN_KEY_CHECKS = 0; DROP TABLE IF EXISTS `" $1 "`;"}' >> $dump_dir/clear_db.sql

	echo "Step 4. Prepare deleting functions"
	$bin_dir/mysql --user=$user --password=$password --host=$host --port=$port --silent --skip-column-names $database --execute "SELECT routine_name FROM information_schema.routines WHERE routine_schema = '$database' AND routine_type = 'FUNCTION'" | gawk '{print "DROP FUNCTION IF EXISTS `" $1 "`;"}' >> $dump_dir/clear_db.sql

	echo "Step 5. Prepare deleting procedures"
	$bin_dir/mysql --user=$user --password=$password --host=$host --port=$port --skip-column-names $database --execute "SELECT routine_name FROM information_schema.routines WHERE routine_schema = '$database' AND routine_type = 'PROCEDURE'" | gawk '{print "DROP PROCEDURE IF EXISTS `" $1 "`;"}' >> $dump_dir/clear_db.sql

	echo "Step 6. Deleting all prepared (executing \"$dump_dir/clear_db.sql\")"
	$bin_dir/mysql --user=$user --password=$password --host=$host --port=$port $database < $dump_dir/clear_db.sql && chmod 666 $dump_dir/clear_db.sql

	echo "Done!"
}

run_import()
{
	echo "Importing database \"$database\"…"

	echo "Step 1. Importing \"$dump_dir/dump1.sql\" (tables structure, functions and procedures)"
	#импортируем структуру таблиц, представления, функции и процедуры
	$bin_dir/mysql --user=$user --password=$password --host=$host --port=$port --database=$database < $dump_dir/dump1.sql

	echo "Step 2. Importing \"$dump_dir/*.txt\" (tables data)"
	run_load_data_infile_build_sql
	#echo ${sql} | $bin_dir/mysql --user=$user --password=$password --host=$host --port=$port --verbose --database=$database && rm -R $dump_dir
	echo ${sql} | $bin_dir/mysql --user=$user --password=$password --host=$host --port=$port --verbose --database=$database

	echo "Step 3. Importing \"$dump_dir/dump2.sql\" (triggers)"
	#импортируем триггеры
	$bin_dir/mysql --user=$user --password=$password --host=$host --port=$port --database=$database < $dump_dir/dump2.sql

	echo "Done!"
}

run_load_data_infile_build_sql()
{
	#disable checking of foreign keys and uniqueness (speed improve)
	sql="SET FOREIGN_KEY_CHECKS = 0, UNIQUE_CHECKS = 0;"

	for f in `ls -1 ${dump_dir}/*.txt`; do
		table=`basename ${f/.txt/}`
		sql="${sql} TRUNCATE TABLE $table;"
		sql="${sql} LOAD DATA INFILE '$f' INTO TABLE $table CHARACTER SET binary;"
	done;

	sql="${sql} SET FOREIGN_KEY_CHECKS = 1, UNIQUE_CHECKS = 1;"
}

progname=$(basename $0)
version=1.2.2

#default values
host="localhost"
user="root"
password=""
port="3306"
ignore_tables=""
dump_dir=`pwd`/dump
bin_dir="/usr/bin"

SHORTOPTS="hH:P:u:p:d:i:b:"
LONGOPTS="help,host:,port:,user:,password:,ignore-tables:,dump-dir:,bin-dir:"

if $(getopt -T >/dev/null 2>&1) ; [ $? = 4 ] ; then
	# New longopts getopt.
	OPTS=$(getopt -o $SHORTOPTS --long $LONGOPTS -n "$progname" -- "$@")
else
	# Old classic getopt.
	# Special handling for --help on old getopt.
	case $1 in --help) print_help ; exit 0 ;; esac
	OPTS=$(getopt $SHORTOPTS "$@")
fi

command="$1"
database="$2"

shift 2

eval set -- "$OPTS"

while [ $# -gt 0 ]; do
	: debug: $1
	case $1 in
		-h|--help)
			print_help
			exit 0
			;;
		-H|--host)
			host="$2"
			shift 2
			;;
		-P|--port)
			port="$2"
			shift 2
			;;
		-u|--user)
			user="$2"
			shift 2
			;;
		-p|--password)
			password="$2"
			shift 2
			;;
		-i|--ignore-tables)
			ignore_tables="$2"
			shift 2
			;;
		-d|--dump-dir)
			dump_dir="$2"
			shift 2
			;;
		-b|--bin-dir)
			bin_dir="$2"
			shift 2
			;;
		--)
			shift
			break
			;;
		*)
			echo "Error processing commands: $1" 1>&2
			exit 1
			;;
	esac
done

if [ $# -lt 2 ]; then
	print_default
    #echo "'./$progname --help' for more information" 1>&2
	exit 1
fi


case $command in
	"export")
		run_export
		exit 0 ;;
	"import")
		run_import
		exit 0 ;;
	"clear")
		run_clear
		exit 0 ;;
	*)
		echo "Unknown command"
		exit 1 ;;
esac
