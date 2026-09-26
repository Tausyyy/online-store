-- ============================================
-- SKU LIFECYCLE
--
-- Draft -> On Sale -> Out of Stock
-- -> On Sale -> Archived
-- ============================================


-- ============================================
-- INITIAL STATE
-- ============================================

SELECT
    sku_id,
    article,
    status,
    stock_quantity
FROM sku
WHERE article = 'JNS-BLU-32';


-- ============================================
-- 1. DRAFT -> ON SALE
-- ============================================

UPDATE sku
SET status = 'on_sale'
WHERE article = 'JNS-BLU-32'
  AND status = 'draft';

SELECT
    sku_id,
    article,
    status,
    stock_quantity
FROM sku
WHERE article = 'JNS-BLU-32';


-- ============================================
-- 2. ON SALE -> OUT OF STOCK
-- ============================================

UPDATE sku
SET
    stock_quantity = 0,
    status = 'out_of_stock'
WHERE article = 'JNS-BLU-32'
  AND status = 'on_sale';

SELECT
    sku_id,
    article,
    status,
    stock_quantity
FROM sku
WHERE article = 'JNS-BLU-32';


-- ============================================
-- 3. OUT OF STOCK -> ON SALE
-- ============================================

UPDATE sku
SET
    stock_quantity = 10,
    status = 'on_sale'
WHERE article = 'JNS-BLU-32'
  AND status = 'out_of_stock';

SELECT
    sku_id,
    article,
    status,
    stock_quantity
FROM sku
WHERE article = 'JNS-BLU-32';


-- ============================================
-- 4. ON SALE -> ARCHIVED
-- ============================================

UPDATE sku
SET status = 'archived'
WHERE article = 'JNS-BLU-32'
  AND status = 'on_sale';

SELECT
    sku_id,
    article,
    status,
    stock_quantity
FROM sku
WHERE article = 'JNS-BLU-32';