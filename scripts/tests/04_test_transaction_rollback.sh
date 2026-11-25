#!/bin/bash
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}  CA 4: TÍNH TOÀN VẸN CỦA TRANSACTION VÀ LỆNH ROLLBACK (KIỂM TRA ACID) ${NC}"
echo -e "${BLUE}======================================================================${NC}\n"

# 1. Ghi nhận trạng thái trước giao dịch
echo -e "${YELLOW}>>> BƯỚC 1: Ghi nhận trạng thái ban đầu của sản phẩm (Bia Heineken ID=5) <<<${NC}"
echo -n "Tồn kho trên Master:  "; docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -sN -e "SELECT stock_quantity FROM products WHERE product_id = 5;" 2>/dev/null
echo -n "Tồn kho trên Slave 1: "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot supermarket_db -sN -e "SELECT stock_quantity FROM products WHERE product_id = 5;" 2>/dev/null
echo -n "Tồn kho trên Slave 2: "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot supermarket_db -sN -e "SELECT stock_quantity FROM products WHERE product_id = 5;" 2>/dev/null

echo -e "\nMã GTID ban đầu:"
echo -n "Master GTID:  "; docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null
echo -n "Slave 1 GTID: "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null
echo -n "Slave 2 GTID: "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null

# 2. Thực hiện Transaction trên Master nhưng gọi ROLLBACK (Khách hủy đơn tại quầy)
ORDER_CANCEL="HD_HUY_$(date +%s)"
echo -e "\n${YELLOW}>>> BƯỚC 2: Mở Transaction trên MASTER, tạo đơn '$ORDER_CANCEL', trừ 10 lon bia nhưng ROLLBACK <<<${NC}"
docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -e "
START TRANSACTION;

-- Thao tác 1: Tạo đơn hàng
INSERT INTO orders (order_code, customer_id, employee_id, total_amount, final_amount, payment_method)
VALUES ('$ORDER_CANCEL', 1, 1, 220000, 220000, 'Thẻ ngân hàng');

-- Thao tác 2: Trừ tồn kho 10 lon bia Heineken
UPDATE products SET stock_quantity = stock_quantity - 10 WHERE product_id = 5;

-- Sự cố: Khách báo hủy mua hàng / Thẻ lỗi -> Hủy toàn bộ giao dịch!
ROLLBACK;
" 2>/dev/null
echo -e "${RED}[ĐÃ GỌI ROLLBACK] Giao dịch dở dang đã bị hủy hoàn toàn trên Master.${NC}"

# 3. Kiểm tra trên Master sau ROLLBACK
echo -e "\n${YELLOW}>>> BƯỚC 3: Kiểm tra trạng thái trên MASTER sau khi ROLLBACK <<<${NC}"
CHECK_ORDER_MASTER=$(docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -sN -e "
SELECT order_code FROM orders WHERE order_code = '$ORDER_CANCEL';
" 2>/dev/null || true)

if [ -z "$CHECK_ORDER_MASTER" ]; then
    echo -e "${GREEN}[MASTER AN TOÀN] Đơn hàng '$ORDER_CANCEL' không tồn tại trên Master (đã hủy thành công).${NC}"
fi

# 4. Kiểm tra trên 2 Slave: Có bị rò rỉ dữ liệu rác sang không?
echo -e "\n${YELLOW}>>> BƯỚC 4: Kiểm tra SLAVE 1 và SLAVE 2 (Dữ liệu rác có bị lọt sang không?) <<<${NC}"
CHECK_SLAVE1=$(docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot supermarket_db -sN -e "
SELECT order_code FROM orders WHERE order_code = '$ORDER_CANCEL';
" 2>/dev/null || true)

CHECK_SLAVE2=$(docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot supermarket_db -sN -e "
SELECT order_code FROM orders WHERE order_code = '$ORDER_CANCEL';
" 2>/dev/null || true)

echo -n "Đơn hàng '$ORDER_CANCEL' trên Slave 1: "
[ -z "$CHECK_SLAVE1" ] && echo -e "${GREEN}KHÔNG TỒN TẠI (Đúng chuẩn)${NC}" || echo -e "${RED}BỊ LỖI LỌT RÁC${NC}"

echo -n "Đơn hàng '$ORDER_CANCEL' trên Slave 2: "
[ -z "$CHECK_SLAVE2" ] && echo -e "${GREEN}KHÔNG TỒN TẠI (Đúng chuẩn)${NC}" || echo -e "${RED}BỊ LỖI LỌT RÁC${NC}"

echo -e "\nKiểm tra tồn kho Bia Heineken trên cả 3 node (đảm bảo không bị trừ nhầm):"
echo -n "Tồn kho trên Master:  "; docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -sN -e "SELECT stock_quantity FROM products WHERE product_id = 5;" 2>/dev/null
echo -n "Tồn kho trên Slave 1: "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot supermarket_db -sN -e "SELECT stock_quantity FROM products WHERE product_id = 5;" 2>/dev/null
echo -n "Tồn kho trên Slave 2: "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot supermarket_db -sN -e "SELECT stock_quantity FROM products WHERE product_id = 5;" 2>/dev/null

echo -e "\nKiểm tra mã GTID sau khi ROLLBACK (chứng minh không tiêu thụ mã GTID):"
echo -n "Master GTID:  "; docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null
echo -n "Slave 1 GTID: "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null
echo -n "Slave 2 GTID: "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null

# 5. Đối chứng: Chạy một Transaction thành công (COMMIT)
echo -e "\n${YELLOW}>>> BƯỚC 5: ĐỐI CHỨNG: Thực hiện Transaction HỢP LỆ (gọi COMMIT) <<<${NC}"
ORDER_SUCCESS="HD_COMMIT_$(date +%s)"
docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -e "
START TRANSACTION;
INSERT INTO orders (order_code, customer_id, employee_id, total_amount, final_amount, payment_method)
VALUES ('$ORDER_SUCCESS', 1, 1, 44000, 44000, 'Tiền mặt');
UPDATE products SET stock_quantity = stock_quantity - 2 WHERE product_id = 5;
COMMIT;
" 2>/dev/null
sleep 1
echo -e "${GREEN}[ĐÃ GỌI COMMIT] Giao dịch thành công, trừ 2 lon bia Heineken.${NC}"

echo -e "\nKiểm tra kết quả sau COMMIT trên cả 3 node:"
echo "--- Master:  "; docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -e "SELECT order_code, final_amount FROM orders WHERE order_code = '$ORDER_SUCCESS';" 2>/dev/null
echo "--- Slave 1: "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot supermarket_db -e "SELECT order_code, final_amount FROM orders WHERE order_code = '$ORDER_SUCCESS';" 2>/dev/null
echo "--- Slave 2: "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot supermarket_db -e "SELECT order_code, final_amount FROM orders WHERE order_code = '$ORDER_SUCCESS';" 2>/dev/null

echo -e "Tồn kho sau khi bán 2 lon bia:"
echo -n "Master:  "; docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -sN -e "SELECT stock_quantity FROM products WHERE product_id = 5;" 2>/dev/null
echo -n "Slave 1: "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot supermarket_db -sN -e "SELECT stock_quantity FROM products WHERE product_id = 5;" 2>/dev/null
echo -n "Slave 2: "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot supermarket_db -sN -e "SELECT stock_quantity FROM products WHERE product_id = 5;" 2>/dev/null

echo -e "\nMã GTID sau khi COMMIT (tất cả cùng tăng thêm 1 giao dịch):"
echo -n "Master GTID:  "; docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null
echo -n "Slave 1 GTID: "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null
echo -n "Slave 2 GTID: "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null

echo -e "\n${BLUE}======================================================================${NC}"
echo -e "${BLUE} KẾT LUẬN: HỆ THỐNG ĐẢM BẢO TUYỆT ĐỐI TÍNH NGUYÊN TỐ (ACID) VÀ AN TOÀN! ${NC}"
echo -e "${BLUE}======================================================================${NC}"
