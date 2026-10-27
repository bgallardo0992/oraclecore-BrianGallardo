-- =====================================================================
-- A.2 - Cuerpo de PKG_TTEM_CATALOG
-- Ejecutar como CORE_DEV DESPUES de pkg_ttem_catalog.pks. Termina con "/" en linea aparte.
-- Las validaciones de negocio y excepciones propias se agregan en A.3: por ahora los
-- errores de integridad (UK, FK, CK, NOT NULL) se propagan tal cual al invocador.
-- =====================================================================
CREATE OR REPLACE PACKAGE BODY pkg_ttem_catalog AS
  PROCEDURE insertar_item (
    p_item     IN  typ_ttem_item,
    p_item_id  OUT ttem_item.item_id%TYPE) IS
  BEGIN
    INSERT INTO ttem_item (item_id, catalog_id, item_code, item_name, item_value,
                           display_order, status, valid_from, valid_to)
    VALUES (seq_ttem_item.NEXTVAL, p_item.catalog_id, UPPER(TRIM(p_item.item_code)),
            TRIM(p_item.item_name), p_item.item_value, NVL(p_item.display_order, 0),
            NVL(p_item.status, c_estado_activo), p_item.valid_from, p_item.valid_to)
    RETURNING item_id INTO p_item_id;
  END insertar_item;
  PROCEDURE actualizar_item (
    p_item  IN typ_ttem_item) IS
  BEGIN
    UPDATE ttem_item
       SET item_name     = TRIM(p_item.item_name),
           item_value    = p_item.item_value,
           display_order = NVL(p_item.display_order, display_order),
           status        = NVL(p_item.status, status),
           valid_from    = NVL(p_item.valid_from, valid_from),
           valid_to      = p_item.valid_to
     WHERE item_id = p_item.item_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE NO_DATA_FOUND;  -- provisional: A.3 lo reemplaza por la excepcion de negocio
    END IF;
  END actualizar_item;
  PROCEDURE eliminar_item (
    p_item_id  IN ttem_item.item_id%TYPE) IS
  BEGIN
    UPDATE ttem_item
       SET status = c_estado_inactivo
     WHERE item_id = p_item_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE NO_DATA_FOUND;  -- provisional: A.3 lo reemplaza por la excepcion de negocio
    END IF;
  END eliminar_item;
  FUNCTION listar_items (
    p_catalog_id  IN ttem_catalog.catalog_id%TYPE)
    RETURN typ_ttem_item_tab IS
    l_items typ_ttem_item_tab;
  BEGIN
    SELECT typ_ttem_item(i.item_id, i.catalog_id, i.item_code, i.item_name, i.item_value,
                         i.display_order, i.status, i.valid_from, i.valid_to)
      BULK COLLECT INTO l_items
      FROM ttem_item i
     WHERE i.catalog_id = p_catalog_id
     ORDER BY i.display_order, i.item_code;
    RETURN l_items;
  END listar_items;
END pkg_ttem_catalog;
/
