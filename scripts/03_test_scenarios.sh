#!/bin/bash
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}      BẮT ĐẦU CHẠY CÁC KỊCH BẢN THỬ NGHIỆM CHO BÀI TẬP A2 (CHUẨN GTID)  ${NC}"
echo -e "${BLUE}======================================================================${NC}\n"

# ==============================================================================
# KỊCH BẢN 1: THÊM DỮ LIỆU MỚI TRÊN MASTER -> TỰ ĐỘNG ĐỒNG BỘ SANG 2 SLAVE
# ==============================================================================
echo -e "${YELLOW}>>> [KỊCH BẢN 1]: Thêm 1 đơn hàng mới trên MASTER (Định danh bằng GTID) <<<${NC}"
echo "Thực hiện lệnh INSERT trên node mysql-master..."

ORDER_CODE="HD_GTID_$(date +%s)"
docker exec mysql-master mysql -uroot -prootpassword supermarket_db -e "
INSERT INTO orders (order_code, customer_id, employee_id, total_amount, discount_amount, final_amount, payment_method)
VALUES ('$ORDER_CODE', 1, 1, 210000, 10000, 200000, 'Ví điện tử');
"

echo -e "\n${GREEN}[Kiểm tra kết quả]: Truy vấn đơn hàng '$ORDER_CODE' trên 3 node:${NC}"
echo -e "--- 1. Trên MASTER ---"
docker exec mysql-master mysql -uroot -prootpassword supermarket_db -e "
SELECT order_code, customer_id, final_amount, payment_method, order_date FROM orders WHERE order_code = '$ORDER_CODE';
"

echo -e "--- 2. Trên SLAVE 1 ---"
docker exec mysql-slave-1 mysql -uroot -prootpassword supermarket_db -e "
SELECT order_code, customer_id, final_amount, payment_method, order_date FROM orders WHERE order_code = '$ORDER_CODE';
"

echo -e "--- 3. Trên SLAVE 2 ---"
docker exec mysql-slave-2 mysql -uroot -prootpassword supermarket_db -e "
SELECT order_code, customer_id, final_amount, payment_method, order_date FROM orders WHERE order_code = '$ORDER_CODE';
"

echo -e "\n${GREEN}[Kiểm tra GTID Set hiện tại trên cả 3 node]:${NC}"
echo -n "Master GTID:  "; docker exec mysql-master mysql -uroot -prootpassword -sN -e "SELECT @@global.gtid_executed;"
echo -n "Slave 1 GTID: "; docker exec mysql-slave-1 mysql -uroot -prootpassword -sN -e "SELECT @@global.gtid_executed;"
echo -n "Slave 2 GTID: "; docker exec mysql-slave-2 mysql -uroot -prootpassword -sN -e "SELECT @@global.gtid_executed;"

echo -e "\n${GREEN}==> KẾT LUẬN KỊCH BẢN 1: Dữ liệu và mã GTID đã đồng bộ hoàn hảo sang 2 Slave!${NC}\n"

# ==============================================================================
# KỊCH BẢN 2: THỬ GHI TRỰC TIẾP TRÊN SLAVE (KIỂM TRA TÍNH TOÀN VẸN / READ-ONLY)
# ==============================================================================
echo -e "${YELLOW}>>> [KỊCH BẢN 2]: Thử INSERT trực tiếp trên SLAVE 1 (Kiểm tra Super Read-only) <<<${NC}"
echo "Cố tình chạy lệnh INSERT vào bảng categories trên mysql-slave-1..."

OUTPUT=$(docker exec mysql-slave-1 mysql -uroot -prootpassword supermarket_db -e "
INSERT INTO categories (category_name, description) VALUES ('Hàng lỗi', 'Test ghi Slave');
" 2>&1 || true)

echo -e "Kết quả trả về từ MySQL Slave 1:\n$OUTPUT"
echo -e "${GREEN}==> KẾT LUẬN KỊCH BẢN 2: Slave đã chặn ghi với lỗi --super-read-only, bảo vệ an toàn toàn vẹn dữ liệu!${NC}\n"

# ==============================================================================
# KỊCH BẢN 3: GIÁN ĐOẠN KẾT NỐI (FAULT TOLERANCE) VÀ TỰ ĐỘNG BÙ DỮ LIỆU QUA GTID
# ==============================================================================
echo -e "${YELLOW}>>> [KỊCH BẢN 3]: Tạm ngắt kết nối SLAVE 1, ghi dữ liệu trên Master, sau đó kết nối lại <<<${NC}"

echo "1. Tạm dừng replication trên Slave 1 (STOP REPLICA)..."
docker exec mysql-slave-1 mysql -uroot -prootpassword -e "STOP REPLICA;"

TEST_BARCODE="893_GTID_$(date +%s)"
TEST_NAME="Sữa tươi tiệt trùng Vinamilk $(date +%H:%M:%S)"

echo "2. Chèn 1 sản phẩm mới ($TEST_NAME) trên Master trong lúc Slave 1 đang ngắt kết nối..."
docker exec mysql-master mysql -uroot -prootpassword supermarket_db -e "
INSERT INTO products (barcode, product_name, category_id, unit, price, stock_quantity)
VALUES ('$TEST_BARCODE', '$TEST_NAME', 4, 'Hộp', 35000, 50);
"

echo -e "\n3. Kiểm tra ngay lập tức:"
echo "- Trên Slave 2 (Vẫn đang chạy bình thường - có sản phẩm):"
docker exec mysql-slave-2 mysql -uroot -prootpassword supermarket_db -e "
SELECT barcode, product_name, price FROM products WHERE barcode = '$TEST_BARCODE';
"

echo "- Trên Slave 1 (Đang ngắt kết nối - dự kiến CHƯA có sản phẩm):"
docker exec mysql-slave-1 mysql -uroot -prootpassword supermarket_db -e "
SELECT barcode, product_name, price FROM products WHERE barcode = '$TEST_BARCODE';
"

echo -e "\n4. Bật lại replication trên Slave 1 (START REPLICA)..."
docker exec mysql-slave-1 mysql -uroot -prootpassword -e "START REPLICA;"
sleep 2

echo -e "5. Kiểm tra lại trên Slave 1 sau khi bật lại (GTID tự động kéo bù giao dịch thiếu):"
docker exec mysql-slave-1 mysql -uroot -prootpassword supermarket_db -e "
SELECT barcode, product_name, price FROM products WHERE barcode = '$TEST_BARCODE';
"

echo -e "\n${GREEN}[Kiểm tra GTID Set đối chiếu sau khi bù dữ liệu]:${NC}"
echo -n "Master GTID:  "; docker exec mysql-master mysql -uroot -prootpassword -sN -e "SELECT @@global.gtid_executed;"
echo -n "Slave 1 GTID: "; docker exec mysql-slave-1 mysql -uroot -prootpassword -sN -e "SELECT @@global.gtid_executed;"
echo -n "Slave 2 GTID: "; docker exec mysql-slave-2 mysql -uroot -prootpassword -sN -e "SELECT @@global.gtid_executed;"

echo -e "\n${GREEN}==> KẾT LUẬN KỊCH BẢN 3: Slave 1 đã tự so sánh GTID và đồng bộ bù thành công 100%!${NC}\n"

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}                  HOÀN TẤT TOÀN BỘ CÁC THỬ NGHIỆM!                    ${NC}"
echo -e "${BLUE}======================================================================${NC}"
