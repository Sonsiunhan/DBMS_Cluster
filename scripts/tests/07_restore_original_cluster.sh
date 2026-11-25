#!/bin/bash
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}     KHÔI PHỤC LẠI KIẾN TRÚC GỐC BAN ĐẦU (1 MASTER - 2 SLAVE)        ${NC}"
echo -e "${BLUE}======================================================================${NC}\n"

# 1. Bật lại container mysql-master
echo -e "${YELLOW}>>> 1. Khởi động lại container mysql-master <<<${NC}"
docker start mysql-master > /dev/null
echo "Đang chờ mysql-master khởi động hoàn toàn..."
until docker exec -e MYSQL_PWD=rootpassword mysql-master mysqladmin ping -uroot >/dev/null 2>&1; do
    sleep 1
done
echo -e "${GREEN}[THÀNH CÔNG] mysql-master đã hoạt động trở lại.${NC}"

MASTER_GTID=$(docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null | tr -d '\n')
MAX_ORDER_ID=$(docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -sN -e "SELECT COALESCE(MAX(order_id),0) + 1 FROM orders;" 2>/dev/null)
MAX_PROD_ID=$(docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -sN -e "SELECT COALESCE(MAX(product_id),0) + 1 FROM products;" 2>/dev/null)

# 2. Khôi phục quyền chỉ đọc cho Slave 1
echo -e "\n${YELLOW}>>> 2. Khôi phục Slave 1 về chế độ Read-only và kết nối lại Master gốc <<<${NC}"
docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot supermarket_db -e "
STOP REPLICA;
SET GLOBAL super_read_only = OFF;
SET GLOBAL read_only = OFF;
DELETE FROM orders WHERE order_code LIKE 'HD_FAILOVER_%';
DELETE FROM products WHERE barcode LIKE '893_FO_%';
ALTER TABLE orders AUTO_INCREMENT = ${MAX_ORDER_ID};
ALTER TABLE products AUTO_INCREMENT = ${MAX_PROD_ID};
RESET REPLICA ALL;
RESET MASTER;
SET GLOBAL gtid_purged = '${MASTER_GTID}';
SET GLOBAL read_only = ON;
SET GLOBAL super_read_only = ON;
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST = 'mysql-master',
  SOURCE_USER = 'repl_user',
  SOURCE_PASSWORD = 'repl_password',
  SOURCE_PORT = 3306,
  SOURCE_AUTO_POSITION = 1;
START REPLICA;
" 2>/dev/null
echo -e "${GREEN}[THÀNH CÔNG] Slave 1 đã quay về làm Replica của Master gốc.${NC}"

# 3. Kết nối lại Slave 2 về Master gốc
echo -e "\n${YELLOW}>>> 3. Kết nối lại Slave 2 về Master gốc qua GTID <<<${NC}"
docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot supermarket_db -e "
STOP REPLICA;
SET GLOBAL super_read_only = OFF;
SET GLOBAL read_only = OFF;
DELETE FROM orders WHERE order_code LIKE 'HD_FAILOVER_%';
DELETE FROM products WHERE barcode LIKE '893_FO_%';
ALTER TABLE orders AUTO_INCREMENT = ${MAX_ORDER_ID};
ALTER TABLE products AUTO_INCREMENT = ${MAX_PROD_ID};
RESET REPLICA ALL;
RESET MASTER;
SET GLOBAL gtid_purged = '${MASTER_GTID}';
SET GLOBAL read_only = ON;
SET GLOBAL super_read_only = ON;
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST = 'mysql-master',
  SOURCE_USER = 'repl_user',
  SOURCE_PASSWORD = 'repl_password',
  SOURCE_PORT = 3306,
  SOURCE_AUTO_POSITION = 1;
START REPLICA;
" 2>/dev/null
echo -e "${GREEN}[THÀNH CÔNG] Slave 2 đã quay về làm Replica của Master gốc.${NC}"

sleep 2
# 4. Kiểm tra trạng thái cả cụm
echo -e "\n${YELLOW}>>> 4. Kiểm tra trạng thái 2 Slave <<<${NC}"
echo "--- Trạng thái Slave 1:"
docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot -e "SHOW REPLICA STATUS\G;" 2>/dev/null | grep -E "Source_Host:|Replica_IO_Running:|Replica_SQL_Running:|Auto_Position:"
echo "--- Trạng thái Slave 2:"
docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot -e "SHOW REPLICA STATUS\G;" 2>/dev/null | grep -E "Source_Host:|Replica_IO_Running:|Replica_SQL_Running:|Auto_Position:"

echo -e "\n${BLUE}======================================================================${NC}"
echo -e "${BLUE}       HỆ THỐNG ĐÃ ĐƯỢC KHÔI PHỤC NGUYÊN TRẠNG 1 MASTER - 2 SLAVE!    ${NC}"
echo -e "${BLUE}======================================================================${NC}"
