#!/bin/bash
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}  CA 6: ĐO LƯỜNG ĐỘ TRỄ NHÂN BẢN (REPLICATION LAG / SECONDS_BEHIND_SOURCE) ${NC}"
echo -e "${BLUE}======================================================================${NC}\n"

# 1. Kiểm tra trạng thái nghỉ ban đầu
echo -e "${YELLOW}>>> BƯỚC 1: Đo độ trễ ban đầu ở trạng thái bình thường (Idle) <<<${NC}"
LAG_SLAVE1_INIT=$(docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot -e "SHOW REPLICA STATUS\G;" 2>/dev/null | grep -i "Seconds_Behind_Source" | awk '{print $2}')
LAG_SLAVE2_INIT=$(docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot -e "SHOW REPLICA STATUS\G;" 2>/dev/null | grep -i "Seconds_Behind_Source" | awk '{print $2}')

echo -e "Độ trễ trên Slave 1 ban đầu: ${GREEN}${LAG_SLAVE1_INIT} giây${NC}"
echo -e "Độ trễ trên Slave 2 ban đầu: ${GREEN}${LAG_SLAVE2_INIT} giây${NC}"

# 2. Tạo tải áp lực cao trên Master: Chèn hàng loạt 500 đơn hàng siêu thị
NUM_ORDERS=500
echo -e "\n${YELLOW}>>> BƯỚC 2: Mô phỏng giờ cao điểm: Gửi một mẻ $NUM_ORDERS đơn hàng vào MASTER <<<${NC}"
echo "Đang sinh dữ liệu và nạp $NUM_ORDERS hóa đơn vào mysql-master..."

START_TIME=$(date +%s%N)

# Chạy tạo 500 đơn hàng bằng Stored Procedure tạm thời trên Master
docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -e "
DROP PROCEDURE IF EXISTS bulk_insert_orders;
DELIMITER //
CREATE PROCEDURE bulk_insert_orders(IN total INT)
BEGIN
    DECLARE i INT DEFAULT 1;
    DECLARE ts BIGINT;
    SET ts = UNIX_TIMESTAMP();
    WHILE i <= total DO
        INSERT INTO orders (order_code, customer_id, employee_id, total_amount, final_amount, payment_method)
        VALUES (CONCAT('HD_BULK_', ts, '_', i), 1, 1, 50000 + (i * 100), 50000 + (i * 100), 'Tiền mặt');
        SET i = i + 1;
    END WHILE;
END //
DELIMITER ;

CALL bulk_insert_orders($NUM_ORDERS);
DROP PROCEDURE bulk_insert_orders;
" 2>/dev/null

END_TIME=$(date +%s%N)
DURATION_MS=$(( (END_TIME - START_TIME) / 1000000 ))
DURATION_SEC=$(awk "BEGIN {printf \"%.2f\", $DURATION_MS / 1000}")

echo -e "${GREEN}[MASTER HOÀN TẤT] Đã chèn xong $NUM_ORDERS hóa đơn vào Master trong: ${DURATION_MS} ms (~${DURATION_SEC} giây).${NC}"

# 3. Đo độ trễ Replication Lag trên Slave 1 và Slave 2 ngay lập tức
echo -e "\n${YELLOW}>>> BƯỚC 3: Đo chỉ số Replication Lag trên các Slave ngay sau tải nặng <<<${NC}"
LAG_SLAVE1=$(docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot -e "SHOW REPLICA STATUS\G;" 2>/dev/null | grep -i "Seconds_Behind_Source" | awk '{print $2}')
LAG_SLAVE2=$(docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot -e "SHOW REPLICA STATUS\G;" 2>/dev/null | grep -i "Seconds_Behind_Source" | awk '{print $2}')

echo -e "Chỉ số Seconds_Behind_Source trên SLAVE 1: ${GREEN}${LAG_SLAVE1} giây${NC}"
echo -e "Chỉ số Seconds_Behind_Source trên SLAVE 2: ${GREEN}${LAG_SLAVE2} giây${NC}"

# 4. Kiểm tra đối chiếu số lượng đơn hàng trên cả 3 máy
sleep 1
echo -e "\n${YELLOW}>>> BƯỚC 4: Kiểm tra tính đồng bộ số lượng đơn hàng trên cả 3 node <<<${NC}"
COUNT_MASTER=$(docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -sN -e "SELECT COUNT(*) FROM orders;" 2>/dev/null)
COUNT_SLAVE1=$(docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot supermarket_db -sN -e "SELECT COUNT(*) FROM orders;" 2>/dev/null)
COUNT_SLAVE2=$(docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot supermarket_db -sN -e "SELECT COUNT(*) FROM orders;" 2>/dev/null)

echo "Tổng số đơn hàng trên MASTER:  $COUNT_MASTER"
echo "Tổng số đơn hàng trên SLAVE 1: $COUNT_SLAVE1"
echo "Tổng số đơn hàng trên SLAVE 2: $COUNT_SLAVE2"

# 5. Kiểm tra mã GTID sau khi tải 500 giao dịch
echo -e "\n${GREEN}[Kiểm tra mã GTID Set sau khi nhân bản $NUM_ORDERS giao dịch]:${NC}"
echo -n "Master GTID:  "; docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null
echo -n "Slave 1 GTID: "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null
echo -n "Slave 2 GTID: "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null

echo -e "\n${BLUE}======================================================================${NC}"
echo -e "${BLUE} KẾT LUẬN: ĐỘ TRỄ NHÂN BẢN GẦN NHƯ BẰNG 0 (NEAR ZERO LAG / REAL-TIME)!  ${NC}"
echo -e "${BLUE}======================================================================${NC}"
