SELECT
    sku_id,
    article,
    status,
    stock_quantity
FROM sku
WHERE article = 'JNS-BLU-32';

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