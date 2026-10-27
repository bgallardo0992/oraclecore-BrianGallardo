-- =====================================================================
-- A.2 - Especificacion de PKG_TTEM_CATALOG (API de mantenimiento de items)
-- Ejecutar como CORE_DEV ANTES del body (.pkb). Termina con "/" en linea aparte.
-- Control transaccional: el package NO hace COMMIT ni ROLLBACK; lo decide el invocador.
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_ttem_catalog AS
  c_estado_activo   CONSTANT CHAR(1) := 'A';
  c_estado_inactivo CONSTANT CHAR(1) := 'I';
  -- Inserta un item. El codigo se normaliza (UPPER/TRIM) y el nombre (TRIM).
  -- p_item.item_id se ignora: el id sale de SEQ_TTEM_ITEM y se devuelve en p_item_id.
  PROCEDURE insertar_item (
    p_item     IN  typ_ttem_item,
    p_item_id  OUT ttem_item.item_id%TYPE);
  -- Actualiza nombre, valor, orden, estado y vigencia del item p_item.item_id.
  -- No permite cambiar el catalogo ni el codigo del item.
  PROCEDURE actualizar_item (
    p_item  IN typ_ttem_item);
  -- Eliminacion LOGICA: marca el item como inactivo (status = 'I').
  PROCEDURE eliminar_item (
    p_item_id  IN ttem_item.item_id%TYPE);
  -- Devuelve los items de un catalogo ordenados por display_order y codigo.
  FUNCTION listar_items (
    p_catalog_id  IN ttem_catalog.catalog_id%TYPE)
    RETURN typ_ttem_item_tab;
END pkg_ttem_catalog;
/
