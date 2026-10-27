-- =====================================================================
-- A.4 - Pruebas de PKG_TTEM_CATALOG.obtener_item_json
-- Ejecutar como CORE_DEV. No deja datos: termina con ROLLBACK.
-- DBeaver: Alt+X y panel Salida. SQL*Plus: SET SERVEROUTPUT ON y "/" tras el END; del bloque.
-- =====================================================================
DECLARE
  l_cat_id   ttem_catalog.catalog_id%TYPE;
  l_usd_id   ttem_item.item_id%TYPE;
  l_item     typ_ttem_item;
  l_json     CLOB;
  l_valido   NUMBER;
  l_faltan   VARCHAR2(200);
  TYPE t_claves IS TABLE OF VARCHAR2(20);
  l_claves   t_claves := t_claves('itemId', 'catalogId', 'catalogCode', 'itemCode', 'name',
                                  'value', 'status', 'validFrom', 'validTo');
BEGIN
  SELECT catalog_id INTO l_cat_id FROM ttem_catalog WHERE catalog_code = 'MONEDA';
  SELECT item_id INTO l_usd_id FROM ttem_item WHERE catalog_id = l_cat_id AND item_code = 'USD';
  -- J1: item existente con validTo nulo
  pkg_ttem_catalog.obtener_item_json(l_usd_id, l_json);
  DBMS_OUTPUT.PUT_LINE('JSON: ' || l_json);
  SELECT CASE WHEN l_json IS JSON THEN 1 ELSE 0 END INTO l_valido FROM dual;
  IF l_valido = 1 THEN
    DBMS_OUTPUT.PUT_LINE('OK    J1 la salida es JSON valido');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FALLA J1 no es JSON valido');
  END IF;
  -- J2: las 9 claves obligatorias estan presentes
  FOR i IN 1 .. l_claves.COUNT LOOP
    IF INSTR(l_json, '"' || l_claves(i) || '":') = 0 THEN
      l_faltan := l_faltan || ' ' || l_claves(i);
    END IF;
  END LOOP;
  IF l_faltan IS NULL THEN
    DBMS_OUTPUT.PUT_LINE('OK    J2 las 9 claves obligatorias estan presentes');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FALLA J2 faltan:' || l_faltan);
  END IF;
  -- J3: nulo como null JSON y fecha con formato YYYY-MM-DD
  IF INSTR(l_json, '"validTo":null') > 0 AND INSTR(l_json, '"validFrom":"2026-01-01"') > 0 THEN
    DBMS_OUTPUT.PUT_LINE('OK    J3 validTo es null JSON (no omitido) y validFrom es "2026-01-01"');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FALLA J3 ' || l_json);
  END IF;
  -- J4: valor nulo y vigencia hasta informada
  l_item := typ_ttem_item(l_usd_id, NULL, NULL, 'Dolar estadounidense', NULL, NULL, NULL, NULL, DATE '2026-12-31');
  pkg_ttem_catalog.actualizar_item(l_item);
  pkg_ttem_catalog.obtener_item_json(l_usd_id, l_json);
  IF INSTR(l_json, '"value":null') > 0 AND INSTR(l_json, '"validTo":"2026-12-31"') > 0 THEN
    DBMS_OUTPUT.PUT_LINE('OK    J4 value null y validTo "2026-12-31"');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FALLA J4 ' || l_json);
  END IF;
  -- J5: caracteres especiales escapados por JSON_OBJECT (comillas y barra invertida)
  l_item := typ_ttem_item(l_usd_id, NULL, NULL, 'Dolar "USD" \ prueba', 'v', NULL, NULL, NULL, NULL);
  pkg_ttem_catalog.actualizar_item(l_item);
  pkg_ttem_catalog.obtener_item_json(l_usd_id, l_json);
  SELECT CASE WHEN l_json IS JSON THEN 1 ELSE 0 END INTO l_valido FROM dual;
  IF l_valido = 1 AND INSTR(l_json, '\"USD\"') > 0 THEN
    DBMS_OUTPUT.PUT_LINE('OK    J5 comillas y barra invertida escapadas: JSON sigue siendo valido');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FALLA J5 ' || l_json);
  END IF;
  -- J6: item inexistente -> excepcion de negocio documentada, sin JSON
  l_json := NULL;  -- ante una excepcion Oracle no copia el OUT: el invocador conserva su valor
  BEGIN
    pkg_ttem_catalog.obtener_item_json(-999, l_json);
    DBMS_OUTPUT.PUT_LINE('FALLA J6 no lanzo error');
  EXCEPTION
    WHEN pkg_ttem_catalog.e_item_no_existe THEN
      IF SQLCODE = -20101 AND l_json IS NULL THEN
        DBMS_OUTPUT.PUT_LINE('OK    J6 item inexistente -> ORA-20101 y p_json nulo');
      ELSE
        DBMS_OUTPUT.PUT_LINE('FALLA J6 sqlcode=' || SQLCODE);
      END IF;
  END;
  ROLLBACK;
  DBMS_OUTPUT.PUT_LINE('ROLLBACK ejecutado: no quedan datos de prueba.');
END;
SELECT item_id, item_code, item_name, valid_to FROM ttem_item WHERE item_code = 'USD';
