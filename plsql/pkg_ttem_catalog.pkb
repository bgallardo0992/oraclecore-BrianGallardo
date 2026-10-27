-- =====================================================================
-- PKG_TTEM_CATALOG - Cuerpo (A.2 CRUD + A.3 validaciones y excepciones propias)
-- Ejecutar como CORE_DEV DESPUES de pkg_ttem_catalog.pks. Termina con "/" en linea aparte.
-- Patron de manejo de errores de cada operacion de escritura:
--   * SAVEPOINT propio al entrar.
--   * WHEN OTHERS: ROLLBACK TO savepoint y SIEMPRE se relanza: si es error de negocio
--     (-20100..-20199) se relanza tal cual (RAISE); si es tecnico se envuelve en -20900
--     conservando el mensaje original (SQLERRM) y la pila de errores (keep_errors = TRUE).
-- =====================================================================
CREATE OR REPLACE PACKAGE BODY pkg_ttem_catalog AS
  FUNCTION es_error_negocio (p_codigo IN PLS_INTEGER) RETURN BOOLEAN IS
  BEGIN
    RETURN p_codigo BETWEEN -20199 AND -20100;
  END es_error_negocio;
  PROCEDURE validar_catalogo_existe (p_catalog_id IN ttem_catalog.catalog_id%TYPE) IS
    l_existe PLS_INTEGER;
  BEGIN
    SELECT 1 INTO l_existe FROM ttem_catalog WHERE catalog_id = p_catalog_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(c_err_catalogo_no_existe,
        'El catalogo ' || NVL(TO_CHAR(p_catalog_id), 'NULL') || ' no existe');
  END validar_catalogo_existe;
  -- Existe y esta activo: regla de negocio de A.3 para poder agregar items.
  PROCEDURE validar_catalogo_activo (p_catalog_id IN ttem_catalog.catalog_id%TYPE) IS
    l_estado ttem_catalog.status%TYPE;
  BEGIN
    SELECT status INTO l_estado FROM ttem_catalog WHERE catalog_id = p_catalog_id;
    IF l_estado <> c_estado_activo THEN
      RAISE_APPLICATION_ERROR(c_err_catalogo_inactivo,
        'El catalogo ' || p_catalog_id || ' esta inactivo y no admite items nuevos');
    END IF;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(c_err_catalogo_no_existe,
        'El catalogo ' || NVL(TO_CHAR(p_catalog_id), 'NULL') || ' no existe');
  END validar_catalogo_activo;
  PROCEDURE validar_codigo (p_codigo IN VARCHAR2) IS
  BEGIN
    IF TRIM(p_codigo) IS NULL THEN
      RAISE_APPLICATION_ERROR(c_err_codigo_obligatorio, 'El codigo del item es obligatorio');
    END IF;
  END validar_codigo;
  PROCEDURE validar_nombre (p_nombre IN VARCHAR2) IS
  BEGIN
    IF TRIM(p_nombre) IS NULL THEN
      RAISE_APPLICATION_ERROR(c_err_nombre_obligatorio, 'El nombre del item es obligatorio');
    END IF;
  END validar_nombre;
  PROCEDURE validar_estado (p_estado IN CHAR) IS
  BEGIN
    IF p_estado IS NOT NULL AND p_estado NOT IN (c_estado_activo, c_estado_inactivo) THEN
      RAISE_APPLICATION_ERROR(c_err_estado_invalido,
        'Estado invalido [' || p_estado || ']: use A (activo) o I (inactivo)');
    END IF;
  END validar_estado;
  PROCEDURE validar_vigencia (p_desde IN DATE, p_hasta IN DATE) IS
  BEGIN
    IF p_desde IS NULL THEN
      RAISE_APPLICATION_ERROR(c_err_vigencia_invalida, 'La vigencia desde es obligatoria');
    END IF;
    IF p_hasta IS NOT NULL AND p_hasta < p_desde THEN
      RAISE_APPLICATION_ERROR(c_err_vigencia_invalida,
        'La vigencia hasta (' || TO_CHAR(p_hasta, 'YYYY-MM-DD') ||
        ') es anterior a la vigencia desde (' || TO_CHAR(p_desde, 'YYYY-MM-DD') || ')');
    END IF;
  END validar_vigencia;
  PROCEDURE insertar_item (
    p_item     IN  typ_ttem_item,
    p_item_id  OUT ttem_item.item_id%TYPE) IS
    l_codigo ttem_item.item_code%TYPE;
  BEGIN
    SAVEPOINT sp_insertar_item;
    p_item_id := NULL;
    validar_catalogo_activo(p_item.catalog_id);
    validar_codigo(p_item.item_code);
    validar_nombre(p_item.item_name);
    validar_estado(p_item.status);
    validar_vigencia(p_item.valid_from, p_item.valid_to);
    l_codigo := UPPER(TRIM(p_item.item_code));
    BEGIN
      INSERT INTO ttem_item (item_id, catalog_id, item_code, item_name, item_value,
                             display_order, status, valid_from, valid_to)
      VALUES (seq_ttem_item.NEXTVAL, p_item.catalog_id, l_codigo,
              TRIM(p_item.item_name), p_item.item_value, NVL(p_item.display_order, 0),
              NVL(p_item.status, c_estado_activo), p_item.valid_from, p_item.valid_to)
      RETURNING item_id INTO p_item_id;
    EXCEPTION
      -- La UK es la garantia real (tambien ante concurrencia); aqui solo se traduce el error.
      WHEN DUP_VAL_ON_INDEX THEN
        RAISE_APPLICATION_ERROR(c_err_item_duplicado,
          'El codigo ' || l_codigo || ' ya existe en el catalogo ' || p_item.catalog_id);
    END;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK TO sp_insertar_item;
      p_item_id := NULL;
      IF es_error_negocio(SQLCODE) THEN
        RAISE;
      ELSE
        RAISE_APPLICATION_ERROR(c_err_tecnico, 'insertar_item: ' || SQLERRM, TRUE);
      END IF;
  END insertar_item;
  PROCEDURE actualizar_item (
    p_item  IN typ_ttem_item) IS
    l_desde_actual ttem_item.valid_from%TYPE;
  BEGIN
    SAVEPOINT sp_actualizar_item;
    BEGIN
      -- Bloquea la fila hasta COMMIT/ROLLBACK del invocador para validar sobre datos estables.
      SELECT valid_from INTO l_desde_actual FROM ttem_item
       WHERE item_id = p_item.item_id FOR UPDATE;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(c_err_item_no_existe,
          'El item ' || NVL(TO_CHAR(p_item.item_id), 'NULL') || ' no existe');
    END;
    validar_nombre(p_item.item_name);
    validar_estado(p_item.status);
    validar_vigencia(NVL(p_item.valid_from, l_desde_actual), p_item.valid_to);
    UPDATE ttem_item
       SET item_name     = TRIM(p_item.item_name),
           item_value    = p_item.item_value,
           display_order = NVL(p_item.display_order, display_order),
           status        = NVL(p_item.status, status),
           valid_from    = NVL(p_item.valid_from, valid_from),
           valid_to      = p_item.valid_to
     WHERE item_id = p_item.item_id;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK TO sp_actualizar_item;
      IF es_error_negocio(SQLCODE) THEN
        RAISE;
      ELSE
        RAISE_APPLICATION_ERROR(c_err_tecnico, 'actualizar_item: ' || SQLERRM, TRUE);
      END IF;
  END actualizar_item;
  PROCEDURE eliminar_item (
    p_item_id  IN ttem_item.item_id%TYPE) IS
    l_id ttem_item.item_id%TYPE;
  BEGIN
    SAVEPOINT sp_eliminar_item;
    BEGIN
      SELECT item_id INTO l_id FROM ttem_item WHERE item_id = p_item_id FOR UPDATE;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(c_err_item_no_existe,
          'El item ' || NVL(TO_CHAR(p_item_id), 'NULL') || ' no existe');
    END;
    UPDATE ttem_item SET status = c_estado_inactivo WHERE item_id = l_id;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK TO sp_eliminar_item;
      IF es_error_negocio(SQLCODE) THEN
        RAISE;
      ELSE
        RAISE_APPLICATION_ERROR(c_err_tecnico, 'eliminar_item: ' || SQLERRM, TRUE);
      END IF;
  END eliminar_item;
  FUNCTION listar_items (
    p_catalog_id  IN ttem_catalog.catalog_id%TYPE)
    RETURN typ_ttem_item_tab IS
    l_items typ_ttem_item_tab;
  BEGIN
    validar_catalogo_existe(p_catalog_id);
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
