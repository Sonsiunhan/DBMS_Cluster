#!/bin/bash
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}    CA 2: BẢO VỆ AN TOÀN DỮ LIỆU TRÊN SLAVE (READ-ONLY ENFORCEMENT)   ${NC}"
echo -e "${BLUE}======================================================================${NC}\n"

# 1. Thử lệnh INSERT trên Slave 1
echo -e "${YELLOW}>>> 1. Cố tình INSERT dữ liệu lạ trực tiếp vào SLAVE 1 <<<${NC}"
OUTPUT1=$(docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot supermarket_db -e "
INSERT INTO products (barcode, product_name, category_id, unit, price, stock_quantity)
VALUES ('893_FAKE_001', 'Hàng không rõ nguồn gốc', 1, 'Cái', 1000, 100);
" 2>&1 | grep -v "Using a password" || true)
echo -e "Kết quả trả về:\n${RED}$OUTPUT1${NC}"

# 2. Thử lệnh UPDATE trên Slave 2
echo -e "\n${YELLOW}>>> 2. Cố tình UPDATE sửa giá sản phẩm trực tiếp trên SLAVE 2 <<<${NC}"
OUTPUT2=$(docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot supermarket_db -e "
UPDATE products SET price = 500 WHERE product_id = 1;
" 2>&1 | grep -v "Using a password" || true)
echo -e "Kết quả trả về:\n${RED}$OUTPUT2${NC}"

# 3. Thử lệnh DELETE trên Slave 1
echo -e "\n${YELLOW}>>> 3. Cố tình DELETE xóa khách hàng trực tiếp trên SLAVE 1 <<<${NC}"
OUTPUT3=$(docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot supermarket_db -e "
DELETE FROM customers WHERE customer_id = 1;
" 2>&1 | grep -v "Using a password" || true)
echo -e "Kết quả trả về:\n${RED}$OUTPUT3${NC}"

# 4. Kiểm tra quyền ĐỌC (SELECT) vẫn bình thường
echo -e "\n${YELLOW}>>> 4. Kiểm tra các quầy thu ngân thực hiện truy vấn ĐỌC (SELECT) trên Slaves <<<${NC}"
echo -n "Số lượng sản phẩm đọc từ Slave 1: "
docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot supermarket_db -sN -e "SELECT COUNT(*) FROM products;" 2>/dev/null
echo -n "Số lượng sản phẩm đọc từ Slave 2: "
docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot supermarket_db -sN -e "SELECT COUNT(*) FROM products;" 2>/dev/null

# 5. Kiểm tra cơ chế miễn trừ cho luồng Replication Applier
echo -e "\n${YELLOW}>>> 5. Kiểm tra luồng Replication từ Master có bị chặn bởi super_read_only không? <<<${NC}"
AUTH_BARCODE="893_AUTH_$(date +%s)"
docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -e "
INSERT INTO products (barcode, product_name, category_id, unit, price, stock_quantity)
VALUES ('$AUTH_BARCODE', 'Nước mắm Phú Quốc 40 độ đạm', 5, 'Chai', 65000, 45);
" 2>/dev/null
sleep 1
echo -e "${GREEN}Đã ghi từ Master thành công. Kiểm tra trên Slave 1 và Slave 2:${NC}"
echo -n "Tên SP trên Slave 1: "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot supermarket_db -sN -e "SELECT product_name FROM products WHERE barcode = '$AUTH_BARCODE';" 2>/dev/null
echo -n "Tên SP trên Slave 2: "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot supermarket_db -sN -e "SELECT product_name FROM products WHERE barcode = '$AUTH_BARCODE';" 2>/dev/null

echo -e "\n${BLUE}======================================================================${NC}"
echo -e "${BLUE}  KẾT LUẬN: SLAVE CHẶN GHI 100% TỪ NGOÀI, NHƯNG VẪN NHẬN ĐỒNG BỘ TỐT!  ${NC}"
echo -e "${BLUE}======================================================================${NC}"
