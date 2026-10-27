-- =====================================================================
-- A.1 - Datos iniciales obligatorios
--   MONEDA: PEN, USD  |  TIPO_COMISION: COM_MANT
-- Ejecutar como CORE_DEV, despues de 02_ttem_triggers.sql (los triggers llenan la auditoria).
-- =====================================================================

INSERT INTO ttem_catalog (catalog_id, catalog_code, catalog_name, description, status)
  VALUES (seq_ttem_catalog.NEXTVAL, 'MONEDA', 'Monedas', 'Monedas admitidas por el core', 'A');
INSERT INTO ttem_catalog (catalog_id, catalog_code, catalog_name, description, status)
  VALUES (seq_ttem_catalog.NEXTVAL, 'TIPO_COMISION', 'Tipos de comision', 'Comisiones aplicables a cuentas y operaciones', 'A');

INSERT INTO ttem_item (item_id, catalog_id, item_code, item_name, item_value, display_order, status, valid_from, valid_to)
  SELECT seq_ttem_item.NEXTVAL, c.catalog_id, 'PEN', 'Sol peruano', 'PEN', 1, 'A', DATE '2026-01-01', NULL
    FROM ttem_catalog c WHERE c.catalog_code = 'MONEDA';
INSERT INTO ttem_item (item_id, catalog_id, item_code, item_name, item_value, display_order, status, valid_from, valid_to)
  SELECT seq_ttem_item.NEXTVAL, c.catalog_id, 'USD', 'Dolar estadounidense', 'USD', 2, 'A', DATE '2026-01-01', NULL
    FROM ttem_catalog c WHERE c.catalog_code = 'MONEDA';
INSERT INTO ttem_item (item_id, catalog_id, item_code, item_name, item_value, display_order, status, valid_from, valid_to)
  SELECT seq_ttem_item.NEXTVAL, c.catalog_id, 'COM_MANT', 'Comision de mantenimiento', '12.50', 1, 'A', DATE '2026-01-01', NULL
    FROM ttem_catalog c WHERE c.catalog_code = 'TIPO_COMISION';

COMMIT;

SELECT c.catalog_id, c.catalog_code, i.item_id, i.item_code, i.item_name, i.item_value,
       i.status, i.valid_from, i.valid_to, i.created_by, i.created_at
  FROM ttem_catalog c JOIN ttem_item i ON i.catalog_id = c.catalog_id
 ORDER BY c.catalog_id, i.display_order;
