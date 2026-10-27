-- =====================================================================
-- A.2 - Pruebas de PKG_TTEM_CATALOG (insertar, listar, actualizar, eliminar logico)
-- Ejecutar como CORE_DEV. No deja datos: termina con ROLLBACK.
-- DBeaver: Alt+X y panel Output. SQL*Plus: SET SERVEROUTPUT ON y "/" tras el END; del bloque.
-- =====================================================================
DECLARE
  l_cat_id  ttem_catalog.catalog_id%TYPE;
  l_item_id ttem_item.item_id%TYPE;
  l_item    typ_ttem_item;
  l_items   typ_ttem_item_tab;
  l_row     ttem_item%ROWTYPE;
BEGIN
  SELECT catalog_id INTO l_cat_id FROM ttem_catalog WHERE catalog_code = 'MONEDA';
  -- P1: insertar con codigo y nombre sucios -> se normalizan
  l_item := typ_ttem_item(NULL, l_cat_id, ' eur ', '  Euro  ', 'EUR', 3, NULL, DATE '2026-10-01', NULL);
  pkg_ttem_catalog.insertar_item(l_item, l_item_id);
  SELECT * INTO l_row FROM ttem_item WHERE item_id = l_item_id;
  IF l_row.item_code = 'EUR' AND l_row.item_name = 'Euro' AND l_row.status = 'A' THEN
    DBMS_OUTPUT.PUT_LINE('OK    P1 insertar normaliza codigo/nombre y estado por defecto A (item_id=' || l_item_id || ')');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FALLA P1 code=[' || l_row.item_code || '] name=[' || l_row.item_name || '] status=' || l_row.status);
  END IF;
  -- P2: listar devuelve la coleccion ordenada (PEN, USD, EUR = 3 items en MONEDA)
  l_items := pkg_ttem_catalog.listar_items(l_cat_id);
  IF l_items.COUNT = 3 AND l_items(1).item_code = 'PEN' AND l_items(3).item_code = 'EUR' THEN
    DBMS_OUTPUT.PUT_LINE('OK    P2 listar_items devuelve ' || l_items.COUNT || ' items ordenados');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FALLA P2 count=' || l_items.COUNT);
  END IF;
  -- P3: actualizar nombre, valor y vigencia
  l_item := typ_ttem_item(l_item_id, NULL, NULL, 'Euro (UE)', 'EUR-UE', NULL, NULL, NULL, DATE '2026-12-31');
  pkg_ttem_catalog.actualizar_item(l_item);
  SELECT * INTO l_row FROM ttem_item WHERE item_id = l_item_id;
  IF l_row.item_name = 'Euro (UE)' AND l_row.item_value = 'EUR-UE' AND l_row.valid_to = DATE '2026-12-31'
     AND l_row.display_order = 3 AND l_row.valid_from = DATE '2026-10-01' THEN
    DBMS_OUTPUT.PUT_LINE('OK    P3 actualizar cambia los campos enviados y conserva orden/vigencia desde');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FALLA P3 name=' || l_row.item_name);
  END IF;
  -- P4: eliminacion logica: la fila sigue existiendo con status I
  pkg_ttem_catalog.eliminar_item(l_item_id);
  SELECT * INTO l_row FROM ttem_item WHERE item_id = l_item_id;
  IF l_row.status = 'I' THEN
    DBMS_OUTPUT.PUT_LINE('OK    P4 eliminar_item es logico: la fila existe con status I');
  ELSE
    DBMS_OUTPUT.PUT_LINE('FALLA P4 status=' || l_row.status);
  END IF;
  -- P5: un error de integridad se propaga (codigo duplicado -> ORA-00001)
  BEGIN
    l_item := typ_ttem_item(NULL, l_cat_id, 'pen', 'Duplicado', NULL, 9, NULL, DATE '2026-01-01', NULL);
    pkg_ttem_catalog.insertar_item(l_item, l_item_id);
    DBMS_OUTPUT.PUT_LINE('FALLA P5 no rechazo el duplicado');
  EXCEPTION WHEN DUP_VAL_ON_INDEX THEN
    DBMS_OUTPUT.PUT_LINE('OK    P5 duplicado propagado como ORA-00001 (A.3 lo convertira en error de negocio)');
  END;
  ROLLBACK;
  DBMS_OUTPUT.PUT_LINE('ROLLBACK ejecutado: no quedan datos de prueba.');
END;
SELECT (SELECT COUNT(*) FROM ttem_item) AS items FROM dual;
