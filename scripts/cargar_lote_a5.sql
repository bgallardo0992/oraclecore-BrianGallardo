-- =====================================================================
-- A.5 - Ejecucion REAL de la carga del lote LOTE-2026-10 (con COMMIT) y consultas de verificacion
-- Ejecutar como CORE_DEV. SI MODIFICA DATOS: inserta 5 items, registra 7 rechazos y marca el staging.
-- Para volver al estado inicial use scripts/restablecer_a5.sql.
-- Resultado de control esperado: 5 cargados y 7 rechazados.
-- DBeaver: Alt+X y panel Salida; las consultas de abajo salen en pestañas de resultados.
-- =====================================================================
DECLARE
  l_cargados   PLS_INTEGER;
  l_rechazados PLS_INTEGER;
BEGIN
  pkg_ttem_load.cargar_lote('LOTE-2026-10', 200, l_cargados, l_rechazados);
  COMMIT;  -- el invocador (este script) confirma; el package nunca hace COMMIT
  DBMS_OUTPUT.PUT_LINE('Lote LOTE-2026-10: cargados=' || l_cargados || ' rechazados=' || l_rechazados);
END;
SELECT s.stg_id, s.catalog_code, s.item_code, s.processed_flag, s.processed_at, e.error_code, e.error_message
  FROM ttem_item_stg s
  LEFT JOIN ttem_load_error e ON e.stg_id = s.stg_id
 WHERE s.load_batch = 'LOTE-2026-10'
 ORDER BY s.stg_id;
SELECT processed_flag, COUNT(*) AS registros FROM ttem_item_stg WHERE load_batch = 'LOTE-2026-10' GROUP BY processed_flag ORDER BY processed_flag;
SELECT c.catalog_code, i.item_id, i.item_code, i.item_name, i.item_value, i.valid_from, i.valid_to, i.created_by
  FROM ttem_item i JOIN ttem_catalog c ON c.catalog_id = i.catalog_id
 ORDER BY c.catalog_code, i.item_code;
