#!/bin/bash
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}    CA 5: NÂNG CẤP CẤU TRÚC BẢNG TRỰC TUYẾN (ONLINE DDL: ALTER TABLE) ${NC}"
echo -e "${BLUE}======================================================================${NC}\n"

# Nếu cột expiry_date đã tồn tại từ lần chạy thử trước thì dọn sạch để kịch bản luôn chạy trọn vẹn 5 bước
PRE_COL=$(docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -sN -e "
SELECT COUNT(*) FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = 'supermarket_db' AND TABLE_NAME = 'products' AND COLUMN_NAME = 'expiry_date';
" 2>/dev/null)
if [ "$PRE_COL" -gt 0 ]; then
    docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -e "
    DELETE FROM products WHERE barcode LIKE '893_DDL_%';
    ALTER TABLE products DROP COLUMN expiry_date;
    " 2>/dev/null
    sleep 1
fi

# 1. Kiểm tra cấu trúc hiện tại của bảng products
echo -e "${YELLOW}>>> BƯỚC 1: Kiểm tra cấu trúc bảng 'products' trước khi nâng cấp <<<${NC}"
echo "Kiểm tra xem cột 'expiry_date' (Hạn sử dụng) đã có chưa:"
CHECK_COL_MASTER=$(docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -sN -e "
SELECT COUNT(*) FROM information_schema.COLUMNS 
WHERE TABLE_SCHEMA = 'supermarket_db' AND TABLE_NAME = 'products' AND COLUMN_NAME = 'expiry_date';
" 2>/dev/null)

if [ "$CHECK_COL_MASTER" -eq 0 ]; then
    echo -e "${GREEN}[CHƯA CÓ] Bảng products hiện chưa có cột 'expiry_date'.${NC}"
else
    echo -e "${YELLOW}[ĐÃ CÓ] Cột 'expiry_date' đã tồn tại từ lần test trước, ta sẽ kiểm tra tiếp.${NC}"
fi

# 2. Thực hiện lệnh ALTER TABLE trên Master (nếu chưa có)
if [ "$CHECK_COL_MASTER" -eq 0 ]; then
    echo -e "\n${YELLOW}>>> BƯỚC 2: Chạy lệnh ALTER TABLE ADD COLUMN trên MASTER <<<${NC}"
    docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -e "
    ALTER TABLE products ADD COLUMN expiry_date DATE NULL AFTER stock_quantity;
    " 2>/dev/null
    sleep 1
    echo -e "${GREEN}[THÀNH CÔNG] Đã thêm cột 'expiry_date' vào bảng products trên Master.${NC}"
fi

# 3. Kiểm tra xem cấu trúc bảng trên 2 Slave đã tự động cập nhật chưa
echo -e "\n${YELLOW}>>> BƯỚC 3: Kiểm tra cấu trúc bảng trên SLAVE 1 và SLAVE 2 <<<${NC}"
echo "--- 1. Cột 'expiry_date' trên Master:"
docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -e "
DESCRIBE products;
" 2>/dev/null | grep -E "Field|stock_quantity|expiry_date"

echo -e "\n--- 2. Cột 'expiry_date' trên SLAVE 1 (Tự động cập nhật không cần can thiệp):"
docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot supermarket_db -e "
DESCRIBE products;
" 2>/dev/null | grep -E "Field|stock_quantity|expiry_date"

echo -e "\n--- 3. Cột 'expiry_date' trên SLAVE 2 (Tự động cập nhật không cần can thiệp):"
docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot supermarket_db -e "
DESCRIBE products;
" 2>/dev/null | grep -E "Field|stock_quantity|expiry_date"

# 4. Thử nghiệm ghi dữ liệu mới có chứa Hạn sử dụng trên Master
echo -e "\n${YELLOW}>>> BƯỚC 4: Chèn sản phẩm mới có Hạn sử dụng (expiry_date) trên Master <<<${NC}"
BARCODE_DDL="893_DDL_$(date +%s)"
EXPIRY_DATE="2026-12-05"

docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -e "
INSERT INTO products (barcode, product_name, category_id, unit, price, stock_quantity, expiry_date)
VALUES ('$BARCODE_DDL', 'Sữa tươi Dalat Milk thanh trùng', 4, 'Hộp', 38000, 25, '$EXPIRY_DATE');
" 2>/dev/null
sleep 1
echo -e "${GREEN}Đã thêm sản phẩm 'Sữa tươi Dalat Milk' (HSD: $EXPIRY_DATE) trên Master.${NC}"

# 5. Kiểm tra dữ liệu trên cả 3 node (bao gồm cả sản phẩm cũ và sản phẩm mới)
echo -e "\n${YELLOW}>>> BƯỚC 5: Truy vấn đối chiếu dữ liệu cột mới trên cả 3 node <<<${NC}"
echo "--- 1. Trên MASTER ---"
docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -e "
SELECT product_id, product_name, price, stock_quantity, expiry_date 
FROM products WHERE barcode = '$BARCODE_DDL';
" 2>/dev/null

echo "--- 2. Trên SLAVE 1 ---"
docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot supermarket_db -e "
SELECT product_id, product_name, price, stock_quantity, expiry_date 
FROM products WHERE barcode = '$BARCODE_DDL';
" 2>/dev/null

echo "--- 3. Trên SLAVE 2 ---"
docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot supermarket_db -e "
SELECT product_id, product_name, price, stock_quantity, expiry_date 
FROM products WHERE barcode = '$BARCODE_DDL';
" 2>/dev/null

echo -e "\n${GREEN}[Kiểm tra mã GTID Set sau khi thực thi DDL]:${NC}"
echo -n "Master GTID:  "; docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null
echo -n "Slave 1 GTID: "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null
echo -n "Slave 2 GTID: "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null

echo -e "\n${BLUE}======================================================================${NC}"
echo -e "${BLUE}  KẾT LUẬN: HỆ THỐNG HỖ TRỢ NÂNG CẤP LƯỢC ĐỒ ONLINE HOÀN TOÀN TỰ ĐỘNG!  ${NC}"
echo -e "${BLUE}======================================================================${NC}"
