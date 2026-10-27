-- =====================================================================
-- Seccion C - Pruebas automaticas de PKG_CORE_SETTLEMENT.transferir
-- Ejecutar como CORE_DEV. No deja datos: termina con ROLLBACK y comprueba que el estado
-- inicial de CORE_ACCOUNT / CORE_TRX se restablece. Usa referencias AUTO-Txxx (no REF-T001/T002),
-- por lo que es independiente de scripts/casos_c_manual.sql.
-- Sin subprogramas locales (DBeaver parte mal los bloques con varias funciones locales):
-- los rechazos se prueban en un bucle sobre una tabla de casos.
-- DBeaver: Alt+X y panel Salida. SQL*Plus: SET SERVEROUTPUT ON y "/" tras el END; del bloque.
-- =====================================================================
DECLARE
  c_a     CONSTANT VARCHAR2(20) := '1910001000011';  -- AHO PEN activa
  c_b     CONSTANT VARCHAR2(20) := '1910002000017';  -- AHO PEN activa
  c_usd   CONSTANT VARCHAR2(20) := '1910001000029';  -- CTE USD activa
  l_id      core_trx.trx_id%TYPE;
  l_trx     core_trx%ROWTYPE;
  l_inicial VARCHAR2(500);
  l_base    VARCHAR2(500);
  l_actual  VARCHAR2(500);
  l_saldo_a NUMBER;
  l_saldo_b NUMBER;
  l_nuevo_a NUMBER;
  l_nuevo_b NUMBER;
  l_seq_ini NUMBER;
  l_seq_fin NUMBER;
  l_n       PLS_INTEGER;
  l_code    NUMBER;
  l_msg     VARCHAR2(500);
BEGIN
  -- Foto del estado: saldos de todas las cuentas y cantidad de movimientos
  SELECT (SELECT LISTAGG(account_no || '=' || TO_CHAR(balance), '|') WITHIN GROUP (ORDER BY account_no)
            FROM core_account) || '|trx=' || (SELECT COUNT(*) FROM core_trx)
    INTO l_inicial FROM dual;
  -- C1: transferencia exitosa
  SELECT balance INTO l_saldo_a FROM core_account WHERE account_no = c_a;
  SELECT balance INTO l_saldo_b FROM core_account WHERE account_no = c_b;
  pkg_core_settlement.transferir(c_a, c_b, 100, 'PEN', 'AUTO-T001', '  prueba exito  ', 'N', l_id);
  SELECT balance INTO l_nuevo_a FROM core_account WHERE account_no = c_a;
  SELECT balance INTO l_nuevo_b FROM core_account WHERE account_no = c_b;
  SELECT * INTO l_trx FROM core_trx WHERE trx_id = l_id;
  SELECT COUNT(*) INTO l_n FROM core_trx WHERE reference = 'AUTO-T001';
  IF l_id IS NOT NULL AND l_nuevo_a = l_saldo_a - 100 AND l_nuevo_b = l_saldo_b + 100 THEN
    DBMS_OUTPUT.PUT_LINE('OK    C1 exito: id devuelto (' || l_id || '), debito y acreditacion (' || l_nuevo_a || ' / ' || l_nuevo_b || ')');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FALLA C1 saldos ' || l_nuevo_a || ' / ' || l_nuevo_b);
  END IF;
  IF l_trx.trx_type = 'TRF' AND l_trx.debit_account_no = c_a AND l_trx.credit_account_no = c_b
     AND l_trx.amount = 100 AND l_trx.currency = 'PEN' AND l_trx.reversal_flag = 'N'
     AND l_trx.reference = 'AUTO-T001' AND l_trx.description = 'prueba exito'
     AND l_trx.reversed_trx_id IS NULL AND l_n = 1 THEN
    DBMS_OUTPUT.PUT_LINE('OK    C1 exito: UNA fila TRF con Debe=origen, Haber=destino, flag N, glosa sin espacios sobrantes');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FALLA C1 fila: ' || l_trx.trx_type || ' filas=' || l_n);
  END IF;
  -- Foto base: a partir de aqui, todo rechazo debe dejar este estado intacto
  SELECT (SELECT LISTAGG(account_no || '=' || TO_CHAR(balance), '|') WITHIN GROUP (ORDER BY account_no)
            FROM core_account) || '|trx=' || (SELECT COUNT(*) FROM core_trx)
    INTO l_base FROM dual;
  -- Rechazos: cada fila es un caso (origen, destino, monto, moneda, referencia, simular, codigo esperado)
  FOR c IN (
    SELECT 1 AS n, 'C2 referencia duplicada' AS caso, '1910001000011' AS orig, '1910002000017' AS dest, 100 AS monto, 'PEN' AS mon, 'AUTO-T001' AS ref, 'N' AS sim, -20206 AS esperado FROM dual
    UNION ALL SELECT 2, 'C3 saldo insuficiente (B tiene 450,50)', '1910002000017', '1910001000011', 5000, 'PEN', 'AUTO-T003', 'N', -20205 FROM dual
    UNION ALL SELECT 3, 'C4 moneda distinta (destino USD)', '1910001000011', '1910001000029', 10, 'PEN', 'AUTO-T004', 'N', -20204 FROM dual
    UNION ALL SELECT 4, 'C5 destino bloqueada', '1910003000013', '1910004000019', 50, 'PEN', 'AUTO-T005', 'N', -20203 FROM dual
    UNION ALL SELECT 5, 'C7 monto cero', '1910001000011', '1910002000017', 0, 'PEN', 'AUTO-T007', 'N', -20200 FROM dual
    UNION ALL SELECT 6, 'C8 monto negativo', '1910001000011', '1910002000017', -5, 'PEN', 'AUTO-T008', 'N', -20200 FROM dual
    UNION ALL SELECT 7, 'C9 monto con 3 decimales', '1910001000011', '1910002000017', 10.505, 'PEN', 'AUTO-T009', 'N', -20200 FROM dual
    UNION ALL SELECT 8, 'C10 cuenta origen inexistente', '9999999999999', '1910002000017', 10, 'PEN', 'AUTO-T010', 'N', -20201 FROM dual
    UNION ALL SELECT 9, 'C11 cuenta destino inexistente', '1910001000011', '9999999999999', 10, 'PEN', 'AUTO-T011', 'N', -20201 FROM dual
    UNION ALL SELECT 10, 'C12 cuentas iguales', '1910001000011', '1910001000011', 10, 'PEN', 'AUTO-T012', 'N', -20202 FROM dual
    UNION ALL SELECT 11, 'C13 cuenta origen cancelada', '1910001000037', '1910001000011', 10, 'PEN', 'AUTO-T013', 'N', -20203 FROM dual
    UNION ALL SELECT 12, 'C14 referencia obligatoria', '1910001000011', '1910002000017', 10, 'PEN', '   ', 'N', -20207 FROM dual
    UNION ALL SELECT 13, 'C15 p_simular_falla invalido', '1910001000011', '1910002000017', 10, 'PEN', 'AUTO-T015', 'X', -20209 FROM dual
    ORDER BY n
  ) LOOP
    l_code := 0;
    l_msg := NULL;
    BEGIN
      pkg_core_settlement.transferir(c.orig, c.dest, c.monto, c.mon, c.ref, NULL, c.sim, l_id);
    EXCEPTION
      WHEN OTHERS THEN
        l_code := SQLCODE;
        l_msg := SQLERRM;
    END;
    SELECT (SELECT LISTAGG(account_no || '=' || TO_CHAR(balance), '|') WITHIN GROUP (ORDER BY account_no)
              FROM core_account) || '|trx=' || (SELECT COUNT(*) FROM core_trx)
      INTO l_actual FROM dual;
    IF l_code = c.esperado THEN
      DBMS_OUTPUT.PUT_LINE('OK    ' || c.caso || ' -> ORA' || l_code);
    ELSE
      DBMS_OUTPUT.PUT_LINE('FALLA ' || c.caso || ' esperado ' || c.esperado || ' real ' || l_code || ' ' || l_msg);
    END IF;
    IF l_actual = l_base THEN
      DBMS_OUTPUT.PUT_LINE('OK    ' || c.caso || ': saldos y CORE_TRX sin cambios');
    ELSE
      DBMS_OUTPUT.PUT_LINE('FALLA ' || c.caso || ': el estado cambio: ' || l_actual);
    END IF;
  END LOOP;
  -- C6: falla simulada despues del debito: nada cambia, y lo de C1 sigue vigente
  SELECT last_number INTO l_seq_ini FROM user_sequences WHERE sequence_name = 'SEQ_CORE_TRX';
  l_code := 0;
  l_msg := NULL;
  BEGIN
    pkg_core_settlement.transferir(c_a, c_b, 100, 'PEN', 'AUTO-T002', NULL, 'S', l_id);
  EXCEPTION
    WHEN OTHERS THEN
      l_code := SQLCODE;
      l_msg := SQLERRM;
  END;
  SELECT (SELECT LISTAGG(account_no || '=' || TO_CHAR(balance), '|') WITHIN GROUP (ORDER BY account_no)
            FROM core_account) || '|trx=' || (SELECT COUNT(*) FROM core_trx)
    INTO l_actual FROM dual;
  SELECT COUNT(*) INTO l_n FROM core_trx WHERE reference = 'AUTO-T002';
  SELECT balance INTO l_nuevo_a FROM core_account WHERE account_no = c_a;
  SELECT balance INTO l_nuevo_b FROM core_account WHERE account_no = c_b;
  SELECT last_number INTO l_seq_fin FROM user_sequences WHERE sequence_name = 'SEQ_CORE_TRX';
  IF l_code = -20208 THEN
    DBMS_OUTPUT.PUT_LINE('OK    C6 falla simulada despues del debito -> ORA' || l_code);
  ELSE
    DBMS_OUTPUT.PUT_LINE('FALLA C6 esperado -20208 real ' || l_code || ' ' || l_msg);
  END IF;
  IF l_actual = l_base AND l_n = 0 THEN
    DBMS_OUTPUT.PUT_LINE('OK    C6 saldos sin cambios y ningun movimiento AUTO-T002 en CORE_TRX (el debito se deshizo)');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FALLA C6 estado: ' || l_actual || ' filas AUTO-T002=' || l_n);
  END IF;
  IF l_nuevo_a = l_saldo_a - 100 AND l_nuevo_b = l_saldo_b + 100 THEN
    DBMS_OUTPUT.PUT_LINE('OK    C6 el trabajo previo del invocador (C1) sigue vigente: el rollback llego solo hasta el savepoint');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FALLA C6 se perdio el trabajo previo: ' || l_nuevo_a || ' / ' || l_nuevo_b);
  END IF;
  IF l_seq_fin = l_seq_ini THEN
    DBMS_OUTPUT.PUT_LINE('OK    C6 la falla ocurre antes de pedir el id: SEQ_CORE_TRX no se consumio (siguiente=' || l_seq_fin || ')');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FALLA C6 la secuencia avanzo de ' || l_seq_ini || ' a ' || l_seq_fin);
  END IF;
  -- C16: exito en USD entre cuentas USD activas, con la moneda en minusculas (se normaliza)
  pkg_core_settlement.transferir(c_usd, '1910003000021', 50, 'usd', 'AUTO-T016', NULL, 'N', l_id);
  SELECT balance INTO l_nuevo_a FROM core_account WHERE account_no = c_usd;
  IF l_id IS NOT NULL AND l_nuevo_a = 1150 THEN
    DBMS_OUTPUT.PUT_LINE('OK    C16 exito en USD con moneda en minusculas (saldo ' || l_nuevo_a || ')');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FALLA C16 saldo ' || l_nuevo_a);
  END IF;
  ROLLBACK;
  SELECT (SELECT LISTAGG(account_no || '=' || TO_CHAR(balance), '|') WITHIN GROUP (ORDER BY account_no)
            FROM core_account) || '|trx=' || (SELECT COUNT(*) FROM core_trx)
    INTO l_actual FROM dual;
  IF l_actual = l_inicial THEN
    DBMS_OUTPUT.PUT_LINE('OK    ROLLBACK final: el estado inicial de CORE_ACCOUNT y CORE_TRX se restablece');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FALLA ROLLBACK final: ' || l_actual);
  END IF;
END;
SELECT account_no, balance FROM core_account WHERE account_no IN ('1910001000011', '1910002000017') ORDER BY account_no;
