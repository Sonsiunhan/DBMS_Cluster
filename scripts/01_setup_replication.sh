#!/bin/bash
set -e

echo "=== 0. Chờ cả 3 container MySQL khởi động sẵn sàng ==="
for node in mysql-master mysql-slave-1 mysql-slave-2; do
    until docker exec -e MYSQL_PWD=rootpassword "$node" mysqladmin ping -uroot >/dev/null 2>&1; do
        sleep 1
    done
done

echo "=== 1. Cấu hình user replication trên Master ==="
docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot -e "
CREATE USER IF NOT EXISTS 'repl_user'@'%' IDENTIFIED WITH mysql_native_password BY 'repl_password';
GRANT REPLICATION SLAVE ON *.* TO 'repl_user'@'%';
FLUSH PRIVILEGES;
"

echo "=== 2. Cấu hình kết nối Replication bằng GTID trên Slave 1 ==="
docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot -e "
STOP REPLICA;
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='mysql-master',
  SOURCE_USER='repl_user',
  SOURCE_PASSWORD='repl_password',
  SOURCE_PORT=3306,
  SOURCE_AUTO_POSITION=1;
START REPLICA;
"

echo "=== 3. Cấu hình kết nối Replication bằng GTID trên Slave 2 ==="
docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot -e "
STOP REPLICA;
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='mysql-master',
  SOURCE_USER='repl_user',
  SOURCE_PASSWORD='repl_password',
  SOURCE_PORT=3306,
  SOURCE_AUTO_POSITION=1;
START REPLICA;
"

sleep 2
echo "=== 4. Kiểm tra trạng thái Slave 1 (GTID) ==="
docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot -e "SHOW REPLICA STATUS\G;" | grep -E "Source_Host:|Replica_IO_Running:|Replica_SQL_Running:|Auto_Position:|Executed_Gtid_Set:|Last_Error:"

echo "=== 5. Kiểm tra trạng thái Slave 2 (GTID) ==="
docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot -e "SHOW REPLICA STATUS\G;" | grep -E "Source_Host:|Replica_IO_Running:|Replica_SQL_Running:|Auto_Position:|Executed_Gtid_Set:|Last_Error:"

echo "=== HOÀN TẤT THIẾT LẬP REPLICATION (CHUẨN GTID) ==="
