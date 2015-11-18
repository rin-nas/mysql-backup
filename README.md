# MySQL database management — clean, import and export data as backup

## Purpose

* Command-line utility to create a hot backup of databases with the possibility of subsequent recovery.
* The script is a high-level wrapper for a `mysqldump` and `mysql` programs.

## Features and advantages

* Export-Import works at 20—35% faster than using a single large *. sql file that combines the structure and data.
Data of tables are stored in *. txt files (tabular format, binary charset). The file names match the names of the tables.
* Description of tables stored in two *. sql files (UTF8 charset). dump1.sql — table structure, functions and procedures; dump1.sql — triggers.
* Export InnoDB tables is performed in a single transaction. This ensures data integrity and does not lock the database during export.

# MySQL управление базой данных — очистка, импорт и экспорт данных как резервная копия

## Назначение

* Консольная утилита для создания горячих резервных копий баз данных с возможностью их последующего восстановления.
* Скрипт является высокоуровневой обёрткой для программ `mysqldump` и `mysql`.

## Возможности и преимущества

* Экспорт-импорт работает на 20—35% быстрее, чем использование одного большого *.sql файла, совмещающего структуру и данные.
* Данные таблиц хранятся в *.txt файлах (tabular format, binary charset). Названия файлов совпадают с названиями таблиц.
* Описание таблиц хранится в двух *.sql файлах (UTF8 charset). dump1.sql — структура таблиц, функции и процедуры; dump1.sql — триггеры.
* Экспорт таблиц InnoDB выполняется в одной транзакции. Это обеспечивает целостность данных и не блокирует работу базы данных во время экспорта.

Project exported from https://code.google.com/p/mysql-backup/
