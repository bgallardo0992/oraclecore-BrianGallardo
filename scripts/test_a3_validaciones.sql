-- =====================================================================
-- A.3 - Pruebas de validaciones y excepciones propias de PKG_TTEM_CATALOG
-- Ejecutar como CORE_DEV. No deja datos: termina con ROLLBACK.
-- DBeaver: Alt+X y panel Salida. SQL*Plus: SET SERVEROUTPUT ON y "/" tras el END; del bloque.
-- =====================================================================
DECLARE
  l_cat_id  ttem_catalog.catalog_id%TYPE;
  l_pen_id  ttem_item.item_id%TYPE;
  l_item_id ttem_item.item_id%TYPE;
  l_item    typ_ttem_item;
  l_items   typ_ttem_item_tab;
  l_n       PLS_INTEGER;
  l_status  ttem_item.status%TYPE;
  PROCEDURE ok(p_caso VARCHAR2, p_esperado NUMBER, p_real NUMBER, p_msg VARCHAR2 DEFAULT NULL) IS
  BEGIN
    IF p_real = p_esperado THEN
      DBMS_OUTPUT.PUT_LINE('OK    ' || p_caso || ' -> ORA' || p_real);
    ELSE
      DBMS_OUTPUT.PUT_LINE('FALLA ' || p_caso || ' esperado ' || p_esperado || ' real ' || p_real || ' ' || p_msg);
    END IF;
  END ok;
BEGIN
  SELECT catalog_id INTO l_cat_id FROM ttem_catalog WHERE catalog_code = 'MONEDA';
  SELECT item_id INTO l_pen_id FROM ttem_item WHERE catalog_id = l_cat_id AND item_code = 'PEN';
  -- V1: catalogo inexistente al insertar
  BEGIN
    l_item := typ_ttem_item(NULL, -999, 'X1', 'Nombre', NULL, 1, NULL, DATE '2026-01-01', NULL);
    pkg_ttem_catalog.insertar_item(l_item, l_item_id);
    DBMS_OUTPUT.PUT_LINE('FALLA V1 no rechazo');
  EXCEPTION WHEN pkg_ttem_catalog.e_catalogo_no_existe THEN ok('V1 catalogo inexistente (insertar)', -20100, SQLCODE);
  END;
  -- V2: codigo vacio (solo espacios)
  BEGIN
    l_item := typ_ttem_item(NULL, l_cat_id, '   ', 'Nombre', NULL, 1, NULL, DATE '2026-01-01', NULL);
    pkg_ttem_catalog.insertar_item(l_item, l_item_id);
    DBMS_OUTPUT.PUT_LINE('FALLA V2 no rechazo');
  EXCEPTION WHEN pkg_ttem_catalog.e_codigo_obligatorio THEN ok('V2 codigo obligatorio', -20104, SQLCODE);
  END;
  -- V3: nombre vacio
  BEGIN
    l_item := typ_ttem_item(NULL, l_cat_id, 'X3', '  ', NULL, 1, NULL, DATE '2026-01-01', NULL);
    pkg_ttem_catalog.insertar_item(l_item, l_item_id);
    DBMS_OUTPUT.PUT_LINE('FALLA V3 no rechazo');
  EXCEPTION WHEN pkg_ttem_catalog.e_nombre_obligatorio THEN ok('V3 nombre obligatorio', -20103, SQLCODE);
  END;
  -- V4: estado invalido
  BEGIN
    l_item := typ_ttem_item(NULL, l_cat_id, 'X4', 'Nombre', NULL, 1, 'Z', DATE '2026-01-01', NULL);
    pkg_ttem_catalog.insertar_item(l_item, l_item_id);
    DBMS_OUTPUT.PUT_LINE('FALLA V4 no rechazo');
  EXCEPTION WHEN pkg_ttem_catalog.e_estado_invalido THEN ok('V4 estado invalido', -20106, SQLCODE);
  END;
  -- V5: vigencia hasta < desde
  BEGIN
    l_item := typ_ttem_item(NULL, l_cat_id, 'X5', 'Nombre', NULL, 1, NULL, DATE '2026-12-01', DATE '2026-06-30');
    pkg_ttem_catalog.insertar_item(l_item, l_item_id);
    DBMS_OUTPUT.PUT_LINE('FALLA V5 no rechazo');
  EXCEPTION WHEN pkg_ttem_catalog.e_vigencia_invalida THEN ok('V5 vigencia hasta < desde', -20105, SQLCODE);
  END;
  -- V6: vigencia desde obligatoria
  BEGIN
    l_item := typ_ttem_item(NULL, l_cat_id, 'X6', 'Nombre', NULL, 1, NULL, NULL, NULL);
    pkg_ttem_catalog.insertar_item(l_item, l_item_id);
    DBMS_OUTPUT.PUT_LINE('FALLA V6 no rechazo');
  EXCEPTION WHEN pkg_ttem_catalog.e_vigencia_invalida THEN ok('V6 vigencia desde obligatoria', -20105, SQLCODE);
  END;
  -- V7: codigo duplicado (con minusculas/espacios: se normaliza a PEN)
  BEGIN
    l_item := typ_ttem_item(NULL, l_cat_id, ' pen ', 'Duplicado', NULL, 9, NULL, DATE '2026-01-01', NULL);
    pkg_ttem_catalog.insertar_item(l_item, l_item_id);
    DBMS_OUTPUT.PUT_LINE('FALLA V7 no rechazo');
  EXCEPTION WHEN pkg_ttem_catalog.e_item_duplicado THEN ok('V7 item duplicado', -20102, SQLCODE);
  END;
  -- V8: actualizar item inexistente
  BEGIN
    l_item := typ_ttem_item(-999, NULL, NULL, 'Nombre', NULL, NULL, NULL, NULL, NULL);
    pkg_ttem_catalog.actualizar_item(l_item);
    DBMS_OUTPUT.PUT_LINE('FALLA V8 no rechazo');
  EXCEPTION WHEN pkg_ttem_catalog.e_item_no_existe THEN ok('V8 item inexistente (actualizar)', -20101, SQLCODE);
  END;
  -- V9: actualizar con hasta anterior al desde existente (2026-01-01)
  BEGIN
    l_item := typ_ttem_item(l_pen_id, NULL, NULL, 'Sol peruano', 'PEN', NULL, NULL, NULL, DATE '2025-12-31');
    pkg_ttem_catalog.actualizar_item(l_item);
    DBMS_OUTPUT.PUT_LINE('FALLA V9 no rechazo');
  EXCEPTION WHEN pkg_ttem_catalog.e_vigencia_invalida THEN ok('V9 vigencia incoherente (actualizar)', -20105, SQLCODE);
  END;
  -- V10: actualizar con nombre vacio
  BEGIN
    l_item := typ_ttem_item(l_pen_id, NULL, NULL, '  ', 'PEN', NULL, NULL, NULL, NULL);
    pkg_ttem_catalog.actualizar_item(l_item);
    DBMS_OUTPUT.PUT_LINE('FALLA V10 no rechazo');
  EXCEPTION WHEN pkg_ttem_catalog.e_nombre_obligatorio THEN ok('V10 nombre vacio (actualizar)', -20103, SQLCODE);
  END;
  -- V11: eliminar item inexistente
  BEGIN
    pkg_ttem_catalog.eliminar_item(-999);
    DBMS_OUTPUT.PUT_LINE('FALLA V11 no rechazo');
  EXCEPTION WHEN pkg_ttem_catalog.e_item_no_existe THEN ok('V11 item inexistente (eliminar)', -20101, SQLCODE);
  END;
  -- V12: listar catalogo inexistente
  BEGIN
    l_items := pkg_ttem_catalog.listar_items(-999);
    DBMS_OUTPUT.PUT_LINE('FALLA V12 no rechazo');
  EXCEPTION WHEN pkg_ttem_catalog.e_catalogo_no_existe THEN ok('V12 catalogo inexistente (listar)', -20100, SQLCODE);
  END;
  -- (El error tecnico -20900 se prueba aparte en scripts/test_a3_error_tecnico.sql)
  -- V14: el rollback del package llega solo hasta su SAVEPOINT: el trabajo previo del invocador sobrevive
  l_item := typ_ttem_item(NULL, l_cat_id, 'PREVIO', 'Item previo del invocador', NULL, 7, NULL, DATE '2026-01-01', NULL);
  pkg_ttem_catalog.insertar_item(l_item, l_item_id);
  BEGIN
    l_item := typ_ttem_item(NULL, l_cat_id, 'PEN', 'Duplicado', NULL, 9, NULL, DATE '2026-01-01', NULL);
    pkg_ttem_catalog.insertar_item(l_item, l_item_id);
  EXCEPTION WHEN pkg_ttem_catalog.e_item_duplicado THEN NULL;
  END;
  SELECT COUNT(*) INTO l_n FROM ttem_item WHERE catalog_id = l_cat_id AND item_code = 'PREVIO';
  IF l_n = 1 THEN
    DBMS_OUTPUT.PUT_LINE('OK    V14 el fallo no revirtio el insert previo del invocador (savepoint)');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FALLA V14 se perdio el trabajo previo');
  END IF;
  -- V15 (positivo): eliminar es idempotente y reactivar con estado A
  pkg_ttem_catalog.eliminar_item(l_pen_id);
  pkg_ttem_catalog.eliminar_item(l_pen_id);
  l_item := typ_ttem_item(l_pen_id, NULL, NULL, 'Sol peruano', 'PEN', NULL, 'A', NULL, NULL);
  pkg_ttem_catalog.actualizar_item(l_item);
  SELECT status INTO l_status FROM ttem_item WHERE item_id = l_pen_id;
  IF l_status = 'A' THEN
    DBMS_OUTPUT.PUT_LINE('OK    V15 eliminar idempotente y reactivacion con actualizar_item');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FALLA V15 status=' || l_status);
  END IF;
  -- V16: catalogo inactivo no admite items nuevos (se inactiva MONEDA solo dentro de esta prueba)
  UPDATE ttem_catalog SET status = 'I' WHERE catalog_id = l_cat_id;
  BEGIN
    l_item := typ_ttem_item(NULL, l_cat_id, 'X16', 'Nombre', NULL, 1, NULL, DATE '2026-01-01', NULL);
    pkg_ttem_catalog.insertar_item(l_item, l_item_id);
    DBMS_OUTPUT.PUT_LINE('FALLA V16 no rechazo');
  EXCEPTION WHEN pkg_ttem_catalog.e_catalogo_inactivo THEN ok('V16 catalogo inactivo (insertar)', -20107, SQLCODE);
  END;
  l_items := pkg_ttem_catalog.listar_items(l_cat_id);
  DBMS_OUTPUT.PUT_LINE('OK    V17 listar_items sigue permitido en catalogo inactivo (' || l_items.COUNT || ' items)');
  ROLLBACK;
  DBMS_OUTPUT.PUT_LINE('ROLLBACK ejecutado: no quedan datos de prueba.');
END;
SELECT (SELECT COUNT(*) FROM ttem_item) AS items FROM dual;
