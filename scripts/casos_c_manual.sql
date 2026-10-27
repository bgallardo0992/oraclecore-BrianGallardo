-- =====================================================================
-- Seccion C - Los 6 casos de prueba del enunciado (ejecucion manual, con COMMIT)
-- Ejecutar como CORE_DEV. SI MODIFICA DATOS: el caso 1 confirma un movimiento (REF-T001).
-- Para volver al estado original use scripts/restablecer_casos_c.sql.
-- Ejecutar los casos EN ORDEN (el caso 2 repite la referencia del caso 1).
-- Cada caso: PREPARACION (saldos antes) -> EJECUCION (bloque) -> VERIFICACION (saldos y CORE_TRX).
-- DBeaver: Alt+X para todo el archivo, o seleccione un caso y use Alt+X. Salida en el panel Salida.
-- =====================================================================

-- ---------- CASO 1: 1910001000011 -> 1910002000017, 100,00 PEN, REF-T001 ----------
-- Esperado: EXITO. Saldos: 1910001000011 pasa de 5250,00 a 5150,00; 1910002000017 de 350,50 a 450,50.
-- Una fila nueva en CORE_TRX (TRF, Debe 1910001000011, Haber 1910002000017, REF-T001).
SELECT account_no, balance FROM core_account WHERE account_no IN ('1910001000011', '1910002000017') ORDER BY account_no;
DECLARE
  l_id core_trx.trx_id%TYPE;
BEGIN
  pkg_core_settlement.transferir('1910001000011', '1910002000017', 100.00, 'PEN', 'REF-T001', 'Caso 1 exito', 'N', l_id);
  COMMIT;  -- el invocador (este script) confirma; el package nunca hace COMMIT
  DBMS_OUTPUT.PUT_LINE('CASO 1 OK: transferencia registrada con trx_id=' || l_id);
EXCEPTION
  WHEN pkg_core_settlement.e_referencia_duplicada THEN
    DBMS_OUTPUT.PUT_LINE('CASO 1: la referencia REF-T001 ya existe (ya se ejecuto este caso). ' || SQLERRM);
END;
SELECT account_no, balance FROM core_account WHERE account_no IN ('1910001000011', '1910002000017') ORDER BY account_no;
SELECT trx_id, debit_account_no, credit_account_no, amount, currency, trx_type, reference, reversal_flag FROM core_trx WHERE reference = 'REF-T001';

-- ---------- CASO 2: repetir la operacion con REF-T001 ----------
-- Esperado: RECHAZO -20206 (referencia duplicada). Saldos sin cambios y CORE_TRX con UNA sola fila REF-T001.
SELECT account_no, balance FROM core_account WHERE account_no IN ('1910001000011', '1910002000017') ORDER BY account_no;
DECLARE
  l_id core_trx.trx_id%TYPE;
BEGIN
  pkg_core_settlement.transferir('1910001000011', '1910002000017', 100.00, 'PEN', 'REF-T001', 'Caso 2 repetida', 'N', l_id);
  DBMS_OUTPUT.PUT_LINE('CASO 2 FALLA: no se rechazo la referencia duplicada');
EXCEPTION
  WHEN pkg_core_settlement.e_referencia_duplicada THEN
    DBMS_OUTPUT.PUT_LINE('CASO 2 OK (rechazo esperado): ' || SQLERRM);
END;
SELECT account_no, balance FROM core_account WHERE account_no IN ('1910001000011', '1910002000017') ORDER BY account_no;
SELECT COUNT(*) AS filas_ref_t001 FROM core_trx WHERE reference = 'REF-T001';

-- ---------- CASO 3: 1910002000017 -> 1910001000011, 5 000,00 PEN ----------
-- Esperado: RECHAZO -20205 (saldo insuficiente: 1910002000017 tiene 450,50). Saldos sin cambios, sin fila nueva.
SELECT account_no, balance FROM core_account WHERE account_no IN ('1910001000011', '1910002000017') ORDER BY account_no;
DECLARE
  l_id core_trx.trx_id%TYPE;
BEGIN
  pkg_core_settlement.transferir('1910002000017', '1910001000011', 5000.00, 'PEN', 'REF-T003', 'Caso 3 saldo', 'N', l_id);
  DBMS_OUTPUT.PUT_LINE('CASO 3 FALLA: no se rechazo por saldo');
EXCEPTION
  WHEN pkg_core_settlement.e_saldo_insuficiente THEN
    DBMS_OUTPUT.PUT_LINE('CASO 3 OK (rechazo esperado): ' || SQLERRM);
END;
SELECT account_no, balance FROM core_account WHERE account_no IN ('1910001000011', '1910002000017') ORDER BY account_no;
SELECT COUNT(*) AS filas_ref_t003 FROM core_trx WHERE reference = 'REF-T003';

-- ---------- CASO 4: 1910001000011 -> 1910001000029, 10,00 PEN ----------
-- Esperado: RECHAZO -20204 (moneda distinta: la cuenta destino es USD). Saldos sin cambios.
SELECT account_no, currency, balance FROM core_account WHERE account_no IN ('1910001000011', '1910001000029') ORDER BY account_no;
DECLARE
  l_id core_trx.trx_id%TYPE;
BEGIN
  pkg_core_settlement.transferir('1910001000011', '1910001000029', 10.00, 'PEN', 'REF-T004', 'Caso 4 moneda', 'N', l_id);
  DBMS_OUTPUT.PUT_LINE('CASO 4 FALLA: no se rechazo por moneda');
EXCEPTION
  WHEN pkg_core_settlement.e_moneda_distinta THEN
    DBMS_OUTPUT.PUT_LINE('CASO 4 OK (rechazo esperado): ' || SQLERRM);
END;
SELECT account_no, currency, balance FROM core_account WHERE account_no IN ('1910001000011', '1910001000029') ORDER BY account_no;
SELECT COUNT(*) AS filas_ref_t004 FROM core_trx WHERE reference = 'REF-T004';

-- ---------- CASO 5: 1910003000013 -> 1910004000019, 50,00 PEN ----------
-- Esperado: RECHAZO -20203 (cuenta destino bloqueada, estado B). Saldos sin cambios.
SELECT account_no, status, balance FROM core_account WHERE account_no IN ('1910003000013', '1910004000019') ORDER BY account_no;
DECLARE
  l_id core_trx.trx_id%TYPE;
BEGIN
  pkg_core_settlement.transferir('1910003000013', '1910004000019', 50.00, 'PEN', 'REF-T005', 'Caso 5 bloqueada', 'N', l_id);
  DBMS_OUTPUT.PUT_LINE('CASO 5 FALLA: no se rechazo la cuenta bloqueada');
EXCEPTION
  WHEN pkg_core_settlement.e_cuenta_no_activa THEN
    DBMS_OUTPUT.PUT_LINE('CASO 5 OK (rechazo esperado): ' || SQLERRM);
END;
SELECT account_no, status, balance FROM core_account WHERE account_no IN ('1910003000013', '1910004000019') ORDER BY account_no;
SELECT COUNT(*) AS filas_ref_t005 FROM core_trx WHERE reference = 'REF-T005';

-- ---------- CASO 6: 1910001000011 -> 1910002000017, 100,00 PEN, REF-T002, FALLA SIMULADA ----------
-- Esperado: ERROR CONTROLADO -20208 tras el debito. Saldos IGUALES a los de antes del caso (5150,00 y 450,50
-- si el caso 1 se ejecuto) y NINGUNA fila REF-T002 en CORE_TRX. El debito se deshizo con ROLLBACK TO SAVEPOINT.
SELECT account_no, balance FROM core_account WHERE account_no IN ('1910001000011', '1910002000017') ORDER BY account_no;
DECLARE
  l_id core_trx.trx_id%TYPE;
BEGIN
  pkg_core_settlement.transferir('1910001000011', '1910002000017', 100.00, 'PEN', 'REF-T002', 'Caso 6 falla simulada', 'S', l_id);
  DBMS_OUTPUT.PUT_LINE('CASO 6 FALLA: no se produjo la falla simulada');
EXCEPTION
  WHEN pkg_core_settlement.e_falla_simulada THEN
    DBMS_OUTPUT.PUT_LINE('CASO 6 OK (error controlado esperado): ' || SQLERRM);
END;
SELECT account_no, balance FROM core_account WHERE account_no IN ('1910001000011', '1910002000017') ORDER BY account_no;
SELECT COUNT(*) AS filas_ref_t002 FROM core_trx WHERE reference = 'REF-T002';
