-- =====================================================================
-- A.5 - Restablece los datos tras ejecutar scripts/cargar_lote_a5.sql (o cualquier carga confirmada)
-- Ejecutar como CORE_DEV. Borra SOLO lo que creo la carga del lote LOTE-2026-10: sus filas de
-- TTEM_LOAD_ERROR y los 5 items cargados (MONEDA: EUR, GBP, CHF; TIPO_COMISION: COM_ATM, COM_TRF_INT),
-- y deja de nuevo los 12 registros del lote como pendientes (N, sin fecha de proceso).
-- SEQ_TTEM_ITEM y SEQ_TTEM_LOAD_ERROR no se revierten. Esperado al final: 3 items, 0 errores, 12 pendientes.
-- =====================================================================
DELETE FROM ttem_load_error WHERE load_batch = 'LOTE-2026-10';
DELETE FROM ttem_item i
 WHERE (i.catalog_id, i.item_code) IN
       (SELECT c.catalog_id, x.item_code
          FROM ttem_catalog c
          JOIN (SELECT 'MONEDA' AS catalog_code, 'EUR' AS item_code FROM dual
                UNION ALL SELECT 'MONEDA', 'GBP' FROM dual
                UNION ALL SELECT 'MONEDA', 'CHF' FROM dual
                UNION ALL SELECT 'TIPO_COMISION', 'COM_ATM' FROM dual
                UNION ALL SELECT 'TIPO_COMISION', 'COM_TRF_INT' FROM dual) x
            ON x.catalog_code = c.catalog_code);
UPDATE ttem_item_stg SET processed_flag = 'N', processed_at = NULL WHERE load_batch = 'LOTE-2026-10';
COMMIT;
SELECT (SELECT COUNT(*) FROM ttem_item) AS items,
       (SELECT COUNT(*) FROM ttem_load_error) AS errores,
       (SELECT COUNT(*) FROM ttem_item_stg WHERE load_batch = 'LOTE-2026-10' AND processed_flag = 'N' AND processed_at IS NULL) AS pendientes
  FROM dual;
