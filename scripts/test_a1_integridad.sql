-- =====================================================================
-- A.1 - Pruebas de integridad del modelo de catalogos
-- Ejecutar como CORE_DEV. No deja datos: termina con ROLLBACK.
-- En DBeaver: ejecutar como script (Alt+X) y abrir el panel Output para ver DBMS_OUTPUT.
-- En SQL*Plus: SET SERVEROUTPUT ON y escribir una linea "/" tras el END; del bloque.
-- =====================================================================
DECLARE
  l_cat_id  ttem_catalog.catalog_id%TYPE;
  l_item_id ttem_item.item_id%TYPE;
  l_row     ttem_item%ROWTYPE;
  PROCEDURE esperar(p_caso VARCHAR2, p_codigo_esperado NUMBER, p_codigo_real NUMBER) IS
  BEGIN
    IF p_codigo_real = p_codigo_esperado THEN
      DBMS_OUTPUT.PUT_LINE('OK    ' || p_caso || ' -> ORA' || p_codigo_real);
    ELSE
      DBMS_OUTPUT.PUT_LINE('FALLA ' || p_caso || ' esperado ' || p_codigo_esperado || ' real ' || p_codigo_real);
    END IF;
  END esperar;
BEGIN
  SELECT catalog_id INTO l_cat_id FROM ttem_catalog WHERE catalog_code = 'MONEDA';
  -- T1: codigo de catalogo duplicado (UK_TTEM_CATALOG_CODE)
  BEGIN
    INSERT INTO ttem_catalog (catalog_id, catalog_code, catalog_name) VALUES (seq_ttem_catalog.NEXTVAL, 'MONEDA', 'Dup');
    DBMS_OUTPUT.PUT_LINE('FALLA T1 no rechazo el duplicado');
  EXCEPTION WHEN DUP_VAL_ON_INDEX THEN esperar('T1 catalogo duplicado', -1, SQLCODE);
  END;
  -- T2: estado de catalogo invalido (CK_TTEM_CATALOG_STATUS)
  BEGIN
    INSERT INTO ttem_catalog (catalog_id, catalog_code, catalog_name, status) VALUES (seq_ttem_catalog.NEXTVAL, 'PRUEBA', 'X', 'Z');
    DBMS_OUTPUT.PUT_LINE('FALLA T2 acepto estado Z');
  EXCEPTION WHEN OTHERS THEN IF SQLCODE = -2290 THEN esperar('T2 estado catalogo invalido', -2290, SQLCODE); ELSE RAISE; END IF;
  END;
  -- T3: codigo de catalogo en minusculas (CK_TTEM_CATALOG_CODE)
  BEGIN
    INSERT INTO ttem_catalog (catalog_id, catalog_code, catalog_name) VALUES (seq_ttem_catalog.NEXTVAL, 'prueba', 'X');
    DBMS_OUTPUT.PUT_LINE('FALLA T3 acepto codigo en minusculas');
  EXCEPTION WHEN OTHERS THEN IF SQLCODE = -2290 THEN esperar('T3 codigo catalogo minusculas', -2290, SQLCODE); ELSE RAISE; END IF;
  END;
  -- T4: item duplicado dentro del mismo catalogo (UK_TTEM_ITEM_CATALOG_CODE)
  BEGIN
    INSERT INTO ttem_item (item_id, catalog_id, item_code, item_name, valid_from) VALUES (seq_ttem_item.NEXTVAL, l_cat_id, 'PEN', 'Dup', DATE '2026-01-01');
    DBMS_OUTPUT.PUT_LINE('FALLA T4 no rechazo item duplicado');
  EXCEPTION WHEN DUP_VAL_ON_INDEX THEN esperar('T4 item duplicado en catalogo', -1, SQLCODE);
  END;
  -- T5: catalogo inexistente (FK_TTEM_ITEM_TTEM_CATALOG)
  BEGIN
    INSERT INTO ttem_item (item_id, catalog_id, item_code, item_name, valid_from) VALUES (seq_ttem_item.NEXTVAL, -999, 'X', 'X', DATE '2026-01-01');
    DBMS_OUTPUT.PUT_LINE('FALLA T5 acepto catalogo inexistente');
  EXCEPTION WHEN OTHERS THEN IF SQLCODE = -2291 THEN esperar('T5 FK catalogo inexistente', -2291, SQLCODE); ELSE RAISE; END IF;
  END;
  -- T6: nombre de item obligatorio (NOT NULL)
  BEGIN
    INSERT INTO ttem_item (item_id, catalog_id, item_code, item_name, valid_from) VALUES (seq_ttem_item.NEXTVAL, l_cat_id, 'NONAME', NULL, DATE '2026-01-01');
    DBMS_OUTPUT.PUT_LINE('FALLA T6 acepto nombre nulo');
  EXCEPTION WHEN OTHERS THEN IF SQLCODE = -1400 THEN esperar('T6 nombre obligatorio', -1400, SQLCODE); ELSE RAISE; END IF;
  END;
  -- T7: vigencia incoherente hasta < desde (CK_TTEM_ITEM_VALID_TO)
  BEGIN
    INSERT INTO ttem_item (item_id, catalog_id, item_code, item_name, valid_from, valid_to) VALUES (seq_ttem_item.NEXTVAL, l_cat_id, 'VIG', 'X', DATE '2026-12-01', DATE '2026-06-30');
    DBMS_OUTPUT.PUT_LINE('FALLA T7 acepto vigencia incoherente');
  EXCEPTION WHEN OTHERS THEN IF SQLCODE = -2290 THEN esperar('T7 vigencia incoherente', -2290, SQLCODE); ELSE RAISE; END IF;
  END;
  -- T8: estado de item invalido (CK_TTEM_ITEM_STATUS)
  BEGIN
    INSERT INTO ttem_item (item_id, catalog_id, item_code, item_name, status, valid_from) VALUES (seq_ttem_item.NEXTVAL, l_cat_id, 'EST', 'X', 'Q', DATE '2026-01-01');
    DBMS_OUTPUT.PUT_LINE('FALLA T8 acepto estado Q');
  EXCEPTION WHEN OTHERS THEN IF SQLCODE = -2290 THEN esperar('T8 estado item invalido', -2290, SQLCODE); ELSE RAISE; END IF;
  END;
  -- T9 (positivo): mismo codigo de item en OTRO catalogo si es valido
  INSERT INTO ttem_item (item_id, catalog_id, item_code, item_name, valid_from)
    SELECT seq_ttem_item.NEXTVAL, catalog_id, 'PEN', 'Mismo codigo otro catalogo', DATE '2026-01-01'
      FROM ttem_catalog WHERE catalog_code = 'TIPO_COMISION';
  DBMS_OUTPUT.PUT_LINE('OK    T9 mismo codigo permitido en otro catalogo');
  -- T10 (positivo): auditoria. El UPDATE intenta alterar created_by y debe ser ignorado.
  SELECT item_id INTO l_item_id FROM ttem_item WHERE catalog_id = l_cat_id AND item_code = 'USD';
  UPDATE ttem_item SET item_name = 'Dolar (modificado)', created_by = 'HACKER' WHERE item_id = l_item_id;
  SELECT * INTO l_row FROM ttem_item WHERE item_id = l_item_id;
  IF l_row.created_by <> 'HACKER' AND l_row.updated_by = SYS_CONTEXT('USERENV', 'SESSION_USER') THEN
    DBMS_OUTPUT.PUT_LINE('OK    T10 auditoria: created_by=' || l_row.created_by || ' updated_by=' || l_row.updated_by);
  ELSE
    DBMS_OUTPUT.PUT_LINE('FALLA T10 auditoria created_by=' || l_row.created_by);
  END IF;
  ROLLBACK;
  DBMS_OUTPUT.PUT_LINE('ROLLBACK ejecutado: no quedan datos de prueba.');
END;
SELECT (SELECT COUNT(*) FROM ttem_catalog) AS catalogos, (SELECT COUNT(*) FROM ttem_item) AS items FROM dual;
