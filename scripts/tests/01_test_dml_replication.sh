#!/bin/bash
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}    CA 1: ĐỒNG BỘ DỮ LIỆU XUÔI (NORMAL DML: INSERT, UPDATE, DELETE)   ${NC}"
echo -e "${BLUE}======================================================================${NC}\n"

# 1. Thao tác INSERT
echo -e "${YELLOW}>>> 1. THAO TÁC INSERT: Thêm khách hàng và xuất hóa đơn mới trên Master <<<${NC}"
ORDER_CODE="HD_CA1_$(date +%s)"
docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -e "
INSERT INTO customers (customer_name, phone, membership_card, points)
VALUES ('Ngô Hoàng Long', CONCAT('0988', SUBSTRING(UNIX_TIMESTAMP(), 5)), CONCAT('VIP', SUBSTRING(UNIX_TIMESTAMP(), 6)), 100);

SET @cust_id = LAST_INSERT_ID();
INSERT INTO orders (order_code, customer_id, employee_id, total_amount, discount_amount, final_amount, payment_method)
VALUES ('$ORDER_CODE', @cust_id, 1, 125000, 0, 125000, 'Chuyển khoản');

SET @order_id = LAST_INSERT_ID();
INSERT INTO order_details (order_id, product_id, quantity, unit_price, subtotal)
VALUES (@order_id, 1, 1, 52000, 52000), (@order_id, 9, 1, 73000, 73000);
"
sleep 1

echo -e "\n${GREEN}[Kiểm tra kết quả INSERT trên cả 3 node]:${NC}"
echo "--- Master ---"
docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -e "SELECT order_code, customer_id, final_amount, payment_method FROM orders WHERE order_code = '$ORDER_CODE';"
echo "--- Slave 1 ---"
docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot supermarket_db -e "SELECT order_code, customer_id, final_amount, payment_method FROM orders WHERE order_code = '$ORDER_CODE';"
echo "--- Slave 2 ---"
docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot supermarket_db -e "SELECT order_code, customer_id, final_amount, payment_method FROM orders WHERE order_code = '$ORDER_CODE';"

# 2. Thao tác UPDATE
echo -e "\n${YELLOW}>>> 2. THAO TÁC UPDATE: Trừ tồn kho và cộng điểm tích lũy trên Master <<<${NC}"
docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -e "
UPDATE products SET stock_quantity = stock_quantity - 1 WHERE product_id IN (1, 9);
"
sleep 1
echo -e "${GREEN}[Kiểm tra tồn kho sau khi UPDATE trên cả 3 node]:${NC}"
echo "--- Master ---"
docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -e "SELECT product_id, product_name, stock_quantity FROM products WHERE product_id IN (1, 9);"
echo "--- Slave 1 ---"
docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot supermarket_db -e "SELECT product_id, product_name, stock_quantity FROM products WHERE product_id IN (1, 9);"
echo "--- Slave 2 ---"
docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot supermarket_db -e "SELECT product_id, product_name, stock_quantity FROM products WHERE product_id IN (1, 9);"

# 3. Thao tác DELETE
echo -e "\n${YELLOW}>>> 3. THAO TÁC DELETE: Xóa dữ liệu hợp lệ trên Master <<<${NC}"
TEMP_CAT="Danh mục tạm $(date +%H:%M:%S)"
docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -e "
INSERT INTO categories (category_name, description) VALUES ('$TEMP_CAT', 'Sự kiện ngắn hạn');
DELETE FROM categories WHERE category_name = '$TEMP_CAT';
"
sleep 1
echo -e "${GREEN}[Kiểm tra DELETE trên cả 3 node (kết quả rỗng = đồng bộ xóa thành công)]:${NC}"
echo "--- Master ---"
docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -e "SELECT * FROM categories WHERE category_name = '$TEMP_CAT';"
echo "--- Slave 1 ---"
docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot supermarket_db -e "SELECT * FROM categories WHERE category_name = '$TEMP_CAT';"
echo "--- Slave 2 ---"
docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot supermarket_db -e "SELECT * FROM categories WHERE category_name = '$TEMP_CAT';"

# 4. Kiểm tra GTID
echo -e "\n${GREEN}[Kiểm tra mã GTID Set trên cả 3 node]:${NC}"
echo -n "Master GTID:  "; docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot -sN -e "SELECT @@global.gtid_executed;"
echo -n "Slave 1 GTID: "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot -sN -e "SELECT @@global.gtid_executed;"
echo -n "Slave 2 GTID: "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot -sN -e "SELECT @@global.gtid_executed;"

echo -e "\n${BLUE}======================================================================${NC}"
echo -e "${BLUE}                    HOÀN TẤT THỬ NGHIỆM CA 1                          ${NC}"
echo -e "${BLUE}======================================================================${NC}"
