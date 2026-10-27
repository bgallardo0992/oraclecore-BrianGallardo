-- =====================================================================
-- A.3 - Prueba del error TECNICO (-20900) de PKG_TTEM_CATALOG
-- Ninguna entrada valida del Object Type provoca un error tecnico (los limites del tipo
-- coinciden con los de la tabla), asi que se fuerza una falla de entorno: se agota
-- SEQ_TTEM_ITEM con ALTER SEQUENCE MAXVALUE y luego SE RESTAURA con NOMAXVALUE.
-- Ejecutar como CORE_DEV sin trabajo pendiente: el ALTER SEQUENCE hace commit implicito.
-- Consume 1 valor de secuencia. No deja filas. DBeaver: Alt+X y panel Salida.
-- SQL*Plus: SET SERVEROUTPUT ON y "/" tras el END; del bloque.
-- =====================================================================
DECLARE
  l_cat_id ttem_catalog.catalog_id%TYPE;
  l_cur    NUMBER;
  l_item   typ_ttem_item;
  l_id     ttem_item.item_id%TYPE;
BEGIN
  SELECT catalog_id INTO l_cat_id FROM ttem_catalog WHERE catalog_code = 'MONEDA';
  l_cur := seq_ttem_item.NEXTVAL;
  EXECUTE IMMEDIATE 'ALTER SEQUENCE seq_ttem_item MAXVALUE ' || TO_CHAR(l_cur);
  BEGIN
    l_item := typ_ttem_item(NULL, l_cat_id, 'TEC1', 'Item tecnico', NULL, 1, NULL, DATE '2026-01-01', NULL);
    pkg_ttem_catalog.insertar_item(l_item, l_id);
    DBMS_OUTPUT.PUT_LINE('FALLA T-TEC no hubo error');
  EXCEPTION
    WHEN pkg_ttem_catalog.e_error_tecnico THEN
      IF SQLCODE = -20900 AND INSTR(SQLERRM, 'ORA-08004') > 0 AND l_id IS NULL THEN
        DBMS_OUTPUT.PUT_LINE('OK    T-TEC error tecnico -> ORA-20900 con el original (ORA-08004) en el mensaje');
      ELSE
        DBMS_OUTPUT.PUT_LINE('FALLA T-TEC mensaje: ' || SQLERRM);
      END IF;
  END;
  EXECUTE IMMEDIATE 'ALTER SEQUENCE seq_ttem_item NOMAXVALUE';
  DBMS_OUTPUT.PUT_LINE('Secuencia restaurada (NOMAXVALUE).');
EXCEPTION
  WHEN OTHERS THEN
    -- Garantiza restaurar la secuencia aunque algo falle y relanza el error original.
    EXECUTE IMMEDIATE 'ALTER SEQUENCE seq_ttem_item NOMAXVALUE';
    RAISE;
END;
SELECT max_value FROM user_sequences WHERE sequence_name = 'SEQ_TTEM_ITEM';
