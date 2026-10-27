-- =====================================================================
-- Seccion C - Restablece los datos tras ejecutar scripts/casos_c_manual.sql
-- Ejecutar como CORE_DEV. Borra SOLO los movimientos de los casos (REF-T001, REF-T002) y devuelve los
-- saldos de las dos cuentas a los valores del Anexo B (5250,00 y 350,50). No modifica estructuras.
-- SEQ_CORE_TRX no se revierte: el siguiente trx_id sera mayor que 1000 (las secuencias no se deshacen).
-- Esperado al final: 11 movimientos, saldos 5250 y 350.5.
-- =====================================================================
DELETE FROM core_trx WHERE reference IN ('REF-T001', 'REF-T002');
UPDATE core_account SET balance = 5250.00 WHERE account_no = '1910001000011';
UPDATE core_account SET balance = 350.50 WHERE account_no = '1910002000017';
COMMIT;
SELECT (SELECT COUNT(*) FROM core_trx) AS movimientos,
       (SELECT balance FROM core_account WHERE account_no = '1910001000011') AS saldo_1910001000011,
       (SELECT balance FROM core_account WHERE account_no = '1910002000017') AS saldo_1910002000017
  FROM dual;
