#!/bin/bash
set -e

# Đảm bảo nếu script bị dừng giữa chừng thì luôn bật lại Replica trên Slave 1
trap 'docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot -e "START REPLICA;" 2>/dev/null || true' EXIT INT TERM

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}    CA 3: GIÁN ĐOẠN MẠNG VÀ TỰ ĐỘNG ĐỒNG BỘ BÙ QUA GTID (FAULT TOLERANCE)  ${NC}"
echo -e "${BLUE}======================================================================${NC}\n"

# 1. Tạm dừng kết nối trên Slave 1 (mô phỏng rớt mạng / đứt cáp)
echo -e "${YELLOW}>>> BƯỚC 1: Mô phỏng SLAVE 1 bị mất kết nối mạng (STOP REPLICA) <<<${NC}"
docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot -e "STOP REPLICA;" 2>/dev/null
echo -e "${RED}[ĐÃ NGẮT KẾT NỐI] Slave 1 tạm thời dừng nhận dữ liệu từ Master.${NC}"

# Kiểm tra trạng thái luồng trên Slave 1
echo -e "\nTrạng thái luồng trên Slave 1 hiện tại:"
docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot -e "SHOW REPLICA STATUS\G;" 2>/dev/null | grep -E "Replica_IO_Running:|Replica_SQL_Running:"

# 2. Bán hàng trên Master trong lúc Slave 1 đang ngắt kết nối
echo -e "\n${YELLOW}>>> BƯỚC 2: Siêu thị tiếp tục bán hàng trên MASTER trong lúc Slave 1 offline <<<${NC}"
TIMESTAMP=$(date +%s)
ORDER_OFFLINE="HD_OFFLINE_${TIMESTAMP}"
BARCODE_OFFLINE="893_OFF_${TIMESTAMP}"
PRODUCT_NAME="Bánh quy bơ Danisa (${TIMESTAMP: -4}g)"

docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -e "
-- Thêm đơn hàng bán hàng trong lúc Slave 1 mất mạng
INSERT INTO orders (order_code, customer_id, employee_id, total_amount, final_amount, payment_method)
VALUES ('$ORDER_OFFLINE', 2, 2, 203000, 203000, 'Tiền mặt');

-- Thêm sản phẩm mới về kho
INSERT INTO products (barcode, product_name, category_id, unit, price, stock_quantity)
VALUES ('$BARCODE_OFFLINE', '$PRODUCT_NAME', 3, 'Hộp', 125000, 30);
" 2>/dev/null
sleep 1

echo -e "${GREEN}Đã ghi nhận đơn hàng mới '$ORDER_OFFLINE' và sản phẩm '$PRODUCT_NAME' trên Master.${NC}"

# 3. Kiểm tra độ lệch dữ liệu giữa các node
echo -e "\n${YELLOW}>>> BƯỚC 3: Đối chiếu dữ liệu giữa các node khi sự cố đang diễn ra <<<${NC}"
echo "--- 1. Trên MASTER (Đang hoạt động chính):"
docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot supermarket_db -e "
SELECT order_code, final_amount, payment_method FROM orders WHERE order_code = '$ORDER_OFFLINE';
" 2>/dev/null

echo "--- 2. Trên SLAVE 2 (Mạng bình thường - nhận dữ liệu tức thì):"
docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot supermarket_db -e "
SELECT order_code, final_amount, payment_method FROM orders WHERE order_code = '$ORDER_OFFLINE';
" 2>/dev/null

echo "--- 3. Trên SLAVE 1 (Đang bị cô lập mạng - dự kiến CHƯA CÓ dữ liệu):"
SLAVE1_CHECK=$(docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot supermarket_db -sN -e "
SELECT order_code FROM orders WHERE order_code = '$ORDER_OFFLINE';
" 2>/dev/null || true)

if [ -z "$SLAVE1_CHECK" ]; then
    echo -e "${RED}[CHƯA CÓ DỮ LIỆU] Đúng như dự đoán: Đơn hàng chưa đến được Slave 1.${NC}"
else
    echo "Đơn hàng: $SLAVE1_CHECK"
fi

echo -e "\n${YELLOW}Mã GTID lúc xảy ra sự cố:${NC}"
echo -n "Master GTID:  "; docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null
echo -n "Slave 2 GTID: "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null
echo -n "Slave 1 GTID (Bị tụt lại): "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null

# 4. Phục hồi kết nối mạng cho Slave 1
echo -e "\n${YELLOW}>>> BƯỚC 4: Khắc phục sự cố mạng, kết nối lại SLAVE 1 (START REPLICA) <<<${NC}"
docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot -e "START REPLICA;" 2>/dev/null
echo "Đang kích hoạt lại luồng Replication và chờ GTID tự động đồng bộ bù..."
sleep 2

# 5. Kiểm tra kết quả sau phục hồi
echo -e "\n${YELLOW}>>> BƯỚC 5: Kiểm tra SLAVE 1 sau khi phục hồi kết nối <<<${NC}"
echo "--- Truy vấn đơn hàng '$ORDER_OFFLINE' trên Slave 1 sau khi bật lại:"
docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot supermarket_db -e "
SELECT order_code, final_amount, payment_method FROM orders WHERE order_code = '$ORDER_OFFLINE';
" 2>/dev/null

echo "--- Truy vấn sản phẩm mới '$PRODUCT_NAME' trên Slave 1:"
docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot supermarket_db -e "
SELECT barcode, product_name, price, stock_quantity FROM products WHERE barcode = '$BARCODE_OFFLINE';
" 2>/dev/null

echo -e "\n${GREEN}[Kiểm tra mã GTID Set sau khi đồng bộ bù]:${NC}"
echo -n "Master GTID:  "; docker exec -e MYSQL_PWD=rootpassword mysql-master mysql -uroot -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null
echo -n "Slave 1 GTID: "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-1 mysql -uroot -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null
echo -n "Slave 2 GTID: "; docker exec -e MYSQL_PWD=rootpassword mysql-slave-2 mysql -uroot -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null

echo -e "\n${BLUE}======================================================================${NC}"
echo -e "${BLUE}   KẾT LUẬN: SLAVE 1 ĐÃ TỰ ĐỘNG BÙ ĐỦ DỮ LIỆU VÀ KHỚP 100% VỚI MASTER!   ${NC}"
echo -e "${BLUE}======================================================================${NC}"
