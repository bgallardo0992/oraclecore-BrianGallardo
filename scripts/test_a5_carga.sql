-- =====================================================================
-- A.5 - Pruebas de PKG_TTEM_LOAD.cargar_lote sobre el lote LOTE-2026-10
-- Ejecutar como CORE_DEV con el modelo minimo de A.1 y TTEM_ITEM_STG sin procesar (12 pendientes).
-- No deja datos: cada ejecucion termina con ROLLBACK. Sin subprogramas locales (compatible con DBeaver).
-- Ejecuta el lote DOS veces: con LIMIT 4 (varios bloques; los duplicados del lote cruzan bloques)
-- y con LIMIT 200 (un solo bloque). Resultado de control esperado: 5 cargados y 7 rechazados.
-- DBeaver: Alt+X y panel Salida. SQL*Plus: SET SERVEROUTPUT ON y "/" tras el END; del bloque.
-- =====================================================================
DECLARE
  c_lote  CONSTANT VARCHAR2(20) := 'LOTE-2026-10';
  c_esp_stg CONSTANT VARCHAR2(1000) :=
    '1:S,2:S,3:S,4:S,5:E-DUPLICADO_LOTE,6:E-CATALOGO_INEXISTENTE,7:E-CODIGO_VACIO,8:E-NOMBRE_VACIO,' ||
    '9:E-FECHA_DESDE_INVALIDA,10:E-VIGENCIA_INCOHERENTE,11:S,12:E-DUPLICADO_EXISTENTE';
  c_esp_items CONSTANT VARCHAR2(2000) :=
    'MONEDA/CHF=franco suizo=CHF=2026-10-01>-;MONEDA/EUR=Euro=EUR=2026-10-01>-;' ||
    'MONEDA/GBP=Libra esterlina=GBP=2026-10-01>-;MONEDA/PEN=Sol peruano=PEN=2026-01-01>-;' ||
    'MONEDA/USD=Dolar estadounidense=USD=2026-01-01>-;' ||
    'TIPO_COMISION/COM_ATM=Comision por retiro en cajero de otra red=8.00=2026-10-01>2026-12-31;' ||
    'TIPO_COMISION/COM_MANT=Comision de mantenimiento=12.50=2026-01-01>-;' ||
    'TIPO_COMISION/COM_TRF_INT=Comision por transferencia interbancaria=7.00=2026-10-01>-';
  l_limit      PLS_INTEGER;
  l_cargados   PLS_INTEGER;
  l_rechazados PLS_INTEGER;
  l_sig        VARCHAR2(4000);
  l_n          PLS_INTEGER;
  l_n2         PLS_INTEGER;
  l_code       NUMBER;
  l_msg        VARCHAR2(500);
BEGIN
  SELECT COUNT(*) INTO l_n FROM ttem_item_stg WHERE load_batch = c_lote AND processed_flag = 'N';
  SELECT COUNT(*) INTO l_n2 FROM ttem_item;
  IF l_n = 12 AND l_n2 = 3 THEN
    DBMS_OUTPUT.PUT_LINE('OK    Precondicion: 12 registros pendientes en staging y 3 items iniciales');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FALLA Precondicion: pendientes=' || l_n || ' items=' || l_n2 ||
                         ' (ejecute scripts/restablecer_a5.sql si ya cargo el lote)');
  END IF;
  FOR r IN 1 .. 2 LOOP
    l_limit := CASE r WHEN 1 THEN 4 ELSE 200 END;
    pkg_ttem_load.cargar_lote(c_lote, l_limit, l_cargados, l_rechazados);
    IF l_cargados = 5 AND l_rechazados = 7 THEN
      DBMS_OUTPUT.PUT_LINE('OK    LIMIT ' || l_limit || ': 5 registros cargados y 7 rechazados');
    ELSE
      DBMS_OUTPUT.PUT_LINE('FALLA LIMIT ' || l_limit || ': cargados=' || l_cargados || ' rechazados=' || l_rechazados);
    END IF;
    -- Cada registro de staging con su marca y su motivo de rechazo
    SELECT LISTAGG(s.stg_id || ':' || s.processed_flag || CASE WHEN e.error_code IS NOT NULL THEN '-' || e.error_code END, ',')
             WITHIN GROUP (ORDER BY s.stg_id)
      INTO l_sig
      FROM ttem_item_stg s
      LEFT JOIN ttem_load_error e ON e.stg_id = s.stg_id
     WHERE s.load_batch = c_lote;
    IF l_sig = c_esp_stg THEN
      DBMS_OUTPUT.PUT_LINE('OK    LIMIT ' || l_limit || ': marca S/E y motivo de rechazo correctos en los 12 registros');
    ELSE
      DBMS_OUTPUT.PUT_LINE('FALLA LIMIT ' || l_limit || ': staging=' || l_sig);
    END IF;
    SELECT COUNT(*) INTO l_n FROM ttem_item_stg WHERE load_batch = c_lote AND processed_at IS NOT NULL;
    SELECT COUNT(*) INTO l_n2 FROM ttem_load_error WHERE load_batch = c_lote;
    IF l_n = 12 AND l_n2 = 7 THEN
      DBMS_OUTPUT.PUT_LINE('OK    LIMIT ' || l_limit || ': processed_at informado en 12 registros y 7 filas en TTEM_LOAD_ERROR');
    ELSE
      DBMS_OUTPUT.PUT_LINE('FALLA LIMIT ' || l_limit || ': processed_at=' || l_n || ' errores=' || l_n2);
    END IF;
    -- Items resultantes: normalizados, el primero del duplicado del lote, y PEN existente intacto
    SELECT LISTAGG(c.catalog_code || '/' || i.item_code || '=' || i.item_name || '=' || i.item_value || '=' ||
                   TO_CHAR(i.valid_from, 'YYYY-MM-DD') || '>' || NVL(TO_CHAR(i.valid_to, 'YYYY-MM-DD'), '-'), ';')
             WITHIN GROUP (ORDER BY c.catalog_code, i.item_code)
      INTO l_sig
      FROM ttem_item i JOIN ttem_catalog c ON c.catalog_id = i.catalog_id;
    IF l_sig = c_esp_items THEN
      DBMS_OUTPUT.PUT_LINE('OK    LIMIT ' || l_limit || ': items normalizados (CHF/franco suizo), COM_TRF_INT=7.00 (la primera), PEN sin cambios');
    ELSE
      DBMS_OUTPUT.PUT_LINE('FALLA LIMIT ' || l_limit || ': items=' || l_sig);
    END IF;
    IF r = 1 THEN
      -- Idempotencia: sin hacer ROLLBACK, una segunda ejecucion no tiene pendientes
      pkg_ttem_load.cargar_lote(c_lote, l_limit, l_cargados, l_rechazados);
      SELECT COUNT(*) INTO l_n FROM ttem_item;
      IF l_cargados = 0 AND l_rechazados = 0 AND l_n = 8 THEN
        DBMS_OUTPUT.PUT_LINE('OK    Segunda ejecucion del mismo lote: 0 cargados, 0 rechazados, sigue habiendo 8 items');
      ELSE
        DBMS_OUTPUT.PUT_LINE('FALLA Segunda ejecucion: cargados=' || l_cargados || ' rechazados=' || l_rechazados || ' items=' || l_n);
      END IF;
    END IF;
    ROLLBACK;
  END LOOP;
  -- El ROLLBACK deja todo como al inicio
  SELECT COUNT(*) INTO l_n FROM ttem_item_stg WHERE load_batch = c_lote AND processed_flag = 'N' AND processed_at IS NULL;
  SELECT COUNT(*) INTO l_n2 FROM ttem_item;
  IF l_n = 12 AND l_n2 = 3 THEN
    DBMS_OUTPUT.PUT_LINE('OK    ROLLBACK final: 12 pendientes en staging, 3 items y 0 errores registrados');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FALLA ROLLBACK final: pendientes=' || l_n || ' items=' || l_n2);
  END IF;
  -- Errores del procedimiento: lote inexistente y limite invalido
  l_code := 0;
  BEGIN
    pkg_ttem_load.cargar_lote('LOTE-NO-EXISTE', 200, l_cargados, l_rechazados);
  EXCEPTION
    WHEN OTHERS THEN
      l_code := SQLCODE;
      l_msg := SQLERRM;
  END;
  IF l_code = -20311 THEN
    DBMS_OUTPUT.PUT_LINE('OK    Lote inexistente -> ORA' || l_code);
  ELSE
    DBMS_OUTPUT.PUT_LINE('FALLA Lote inexistente: codigo ' || l_code || ' ' || l_msg);
  END IF;
  l_code := 0;
  BEGIN
    pkg_ttem_load.cargar_lote(c_lote, 0, l_cargados, l_rechazados);
  EXCEPTION
    WHEN OTHERS THEN
      l_code := SQLCODE;
      l_msg := SQLERRM;
  END;
  IF l_code = -20312 THEN
    DBMS_OUTPUT.PUT_LINE('OK    p_limit = 0 -> ORA' || l_code);
  ELSE
    DBMS_OUTPUT.PUT_LINE('FALLA p_limit = 0: codigo ' || l_code || ' ' || l_msg);
  END IF;
  SELECT COUNT(*) INTO l_n FROM ttem_item_stg WHERE load_batch = c_lote AND processed_flag = 'N';
  IF l_n = 12 THEN
    DBMS_OUTPUT.PUT_LINE('OK    Los errores no dejaron cambios en staging (12 pendientes)');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FALLA Tras los errores hay ' || l_n || ' pendientes');
  END IF;
END;
SELECT COUNT(*) AS pendientes FROM ttem_item_stg WHERE load_batch = 'LOTE-2026-10' AND processed_flag = 'N';
