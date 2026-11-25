#!/bin/bash
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}  CA 7: XỬ LÝ THẢM HỌA KHI MASTER CHẾT HOÀN TOÀN (MANUAL FAILOVER / GTID) ${NC}"
echo -e "${BLUE}======================================================================${NC}\n"

# 1. Đánh sập máy chủ Master (mô phỏng cháy phần cứng / sập nguồn vĩnh viễn)
echo -e "${YELLOW}>>> BƯỚC 1: Đánh sập hoàn toàn máy chủ MASTER (docker stop mysql-master) <<<${NC}"
docker stop mysql-master > /dev/null 2>&1 || true
echo -e "${RED}[SỰ CỐ THẢM HỌA] Máy chủ Master đã CHẾT HOÀN TOÀN (Offline)!${NC}"
echo -n "Kiểm tra kết nối Master: "
if ! docker exec -e MYSQL_PWD=rootpassword mysql-master mysqladmin ping -uroot >/dev/null 2>&1; then
    echo -e "${RED}KHÔNG THỂ TRUY CẬP (Hệ thống mất khả năng ghi)${NC}"
fi

# 2. Thăng hạng Slave 1 lên làm Master mới (Promote Slave 1 to New Master)
echo -e "\n${YELLOW}>>> BƯỚC 2: Thăng hạng SLAVE 1 làm MASTER MỚI (New Primary) <<<${NC}"
docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot -e "
-- Cắt đứt liên kết cũ với Master đã chết
STOP REPLICA;
RESET REPLICA ALL;

-- Mở khóa toàn quyền GHI cho siêu thị
SET GLOBAL super_read_only = OFF;
SET GLOBAL read_only = OFF;

-- Tạo tài khoản để Slave 2 có thể kết nối sang
CREATE USER IF NOT EXISTS 'repl_user'@'%' IDENTIFIED WITH mysql_native_password BY 'repl_password';
GRANT REPLICATION SLAVE ON *.* TO 'repl_user'@'%';
FLUSH PRIVILEGES;
" 2>/dev/null

echo -e "${GREEN}[THÀNH CÔNG] Slave 1 đã được thăng hạng làm Master mới!${NC}"
echo -n "Kiểm tra quyền ghi trên Slave 1: "
READ_ONLY_STATUS=$(docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot -sN -e "SELECT @@global.read_only;" 2>/dev/null)
if [ "$READ_ONLY_STATUS" -eq 0 ]; then
    echo -e "${GREEN}ĐÃ MỞ QUYỀN GHI (read_only = OFF)${NC}"
fi

# 3. Trỏ Slave 2 sang nhận Slave 1 làm Master mới (Tận dụng sức mạnh GTID)
echo -e "\n${YELLOW}>>> BƯỚC 3: Cấu hình SLAVE 2 kết nối sang MASTER MỚI (Slave 1) qua GTID <<<${NC}"
echo "Nhờ cơ chế GTID (MASTER_AUTO_POSITION = 1), Slave 2 tự động so sánh dữ liệu:"
docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot -e "
STOP REPLICA;
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST = 'mysql-slave-1',
  SOURCE_PORT = 3306,
  SOURCE_USER = 'repl_user',
  SOURCE_PASSWORD = 'repl_password',
  SOURCE_AUTO_POSITION = 1;
START REPLICA;
" 2>/dev/null

sleep 2
echo -e "\n${GREEN}[Kiểm tra trạng thái kết nối trên Slave 2]:${NC}"
docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot -e "SHOW REPLICA STATUS\G;" 2>/dev/null | grep -E "Source_Host:|Replica_IO_Running:|Replica_SQL_Running:|Auto_Position:"

# 4. Thử nghiệm xuất đơn hàng mới trên Master mới (Slave 1)
echo -e "\n${YELLOW}>>> BƯỚC 4: Siêu thị bán hàng trở lại: Xuất hóa đơn mới trên MASTER MỚI <<<${NC}"
TIMESTAMP=$(date +%s)
ORDER_FAILOVER="HD_FAILOVER_${TIMESTAMP}"
BARCODE_FAILOVER="893_FO_${TIMESTAMP}"
PRODUCT_NAME="Rượu vang Đà Lạt (${TIMESTAMP: -4}ml)"

docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot supermarket_db -e "
INSERT INTO orders (order_code, customer_id, employee_id, total_amount, final_amount, payment_method)
VALUES ('$ORDER_FAILOVER', 1, 2, 350000, 350000, 'Chuyển khoản');

INSERT INTO products (barcode, product_name, category_id, unit, price, stock_quantity)
VALUES ('$BARCODE_FAILOVER', '$PRODUCT_NAME', 4, 'Chai', 180000, 20);
" 2>/dev/null
sleep 1

echo -e "${GREEN}Đã ghi thành công hóa đơn '$ORDER_FAILOVER' và sản phẩm '$PRODUCT_NAME' trên Master mới (Slave 1).${NC}"

# 5. Kiểm tra dữ liệu tự động đồng bộ sang Slave 2
echo -e "\n${YELLOW}>>> BƯỚC 5: Kiểm tra dữ liệu tự động đồng bộ sang SLAVE 2 <<<${NC}"
echo "--- Truy vấn hóa đơn trên MASTER MỚI (mysql-slave-1):"
docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot supermarket_db -e "
SELECT order_code, final_amount, payment_method FROM orders WHERE order_code = '$ORDER_FAILOVER';
" 2>/dev/null

echo "--- Truy vấn hóa đơn trên SLAVE 2 (mysql-slave-2):"
docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot supermarket_db -e "
SELECT order_code, final_amount, payment_method FROM orders WHERE order_code = '$ORDER_FAILOVER';
" 2>/dev/null

# 6. Minh chứng nguồn gốc GTID mới
echo -e "\n${GREEN}[Minh chứng GTID trên Master mới và Slave 2]:${NC}"
echo -n "Master mới (Slave 1) GTID: "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null
echo -n "Slave 2 GTID:              "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null

echo -e "\n${BLUE}======================================================================${NC}"
echo -e "${BLUE}  KẾT LUẬN: FAILOVER THÀNH CÔNG 100%! HỆ THỐNG ĐÃ SỐNG LẠI HOÀN TOÀN!   ${NC}"
echo -e "${BLUE}======================================================================${NC}"
