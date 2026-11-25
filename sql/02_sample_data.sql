-- ============================================================
-- DỮ LIỆU MẪU CHO SIÊU THỊ (supermarket_db)
-- ============================================================

USE supermarket_db;

-- 1. Thêm danh mục ngành hàng
INSERT INTO categories (category_name, description) VALUES
('Thực phẩm tươi sống', 'Thịt, cá, hải sản, rau củ quả tươi sạch hàng ngày'),
('Hóa mỹ phẩm & Tẩy rửa', 'Xà phòng, nước giặt, dầu gội, sữa tắm, nước lau sàn'),
('Bánh kẹo & Đồ ăn vặt', 'Bánh ngọt, snack, kẹo, socola các loại'),
('Đồ uống & Giải khát', 'Nước ngọt, nước khoáng, trà, bia và nước trái cây'),
('Gia vị & Đồ khô', 'Nước mắm, dầu ăn, đường, muối, mì tôm, gạo');

-- 2. Thêm nhân viên
INSERT INTO employees (employee_name, role, phone, salary) VALUES
('Nguyễn Văn An', 'Thu ngân', '0901234567', 7500000),
('Trần Thị Bích', 'Thu ngân', '0912345678', 7500000),
('Lê Hoàng Nam', 'Quản lý ca', '0987654321', 12000000);

-- 3. Thêm khách hàng thân thiết
INSERT INTO customers (customer_name, phone, membership_card, points) VALUES
('Phạm Minh Tuấn', '0933112233', 'VIP001', 150),
('Vũ Thị Mai', '0944223344', 'MEM002', 45),
('Đặng Quốc Huy', '0977889900', 'MEM003', 80);

-- 4. Thêm sản phẩm
INSERT INTO products (barcode, product_name, category_id, unit, price, stock_quantity) VALUES
('893456701', 'Dầu ăn Neptune Gold 1L', 5, 'Chai', 52000, 120),
('893456702', 'Nước mắm Nam Ngư 750ml', 5, 'Chai', 38000, 200),
('893456703', 'Gạo ST25 túi 5kg', 5, 'Túi', 185000, 50),
('893456704', 'Nước ngọt Coca Cola 320ml', 4, 'Lon', 10000, 500),
('893456705', 'Bia Heineken lon 330ml', 4, 'Lon', 22000, 300),
('893456706', 'Snack khoai tây OStar vị kim chi', 3, 'Gói', 14000, 150),
('893456707', 'Nước giặt OMO Matic cửa trên 2kg', 2, 'Túi', 145000, 80),
('893456708', 'Dầu gội Clear Men 630g', 2, 'Chai', 179000, 60),
('893456709', 'Thịt ba rọi heo CP (500g)', 1, 'Hộp', 75000, 40),
('893456710', 'Bắp cải trắng Đà Lạt (kg)', 1, 'Kg', 18000, 100);

-- 5. Thêm hóa đơn mẫu
INSERT INTO orders (order_code, customer_id, employee_id, total_amount, discount_amount, final_amount, payment_method) VALUES
('HD20261119001', 1, 1, 289000, 10000, 279000, 'Chuyển khoản'),
('HD20261119002', 2, 2, 88000, 0, 88000, 'Tiền mặt');

-- 6. Thêm chi tiết hóa đơn
-- Chi tiết hóa đơn 1: 1 Dầu ăn (52k) + 1 Gạo ST25 (185k) + 2 Lon Coca (20k) + 1 Hộp ba rọi (75k) = 332k (tính mẫu)
INSERT INTO order_details (order_id, product_id, quantity, unit_price, subtotal) VALUES
(1, 1, 1, 52000, 52000),
(1, 3, 1, 185000, 185000),
(1, 4, 2, 10000, 20000),
(1, 9, 1, 32000, 32000);

-- Chi tiết hóa đơn 2: 2 Nước mắm Nam Ngư (76k) + 1 Snack OStar (14k)
INSERT INTO order_details (order_id, product_id, quantity, unit_price, subtotal) VALUES
(2, 2, 2, 37000, 74000),
(2, 6, 1, 14000, 14000);
