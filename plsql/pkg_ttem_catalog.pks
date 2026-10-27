-- =====================================================================
-- PKG_TTEM_CATALOG - Especificacion (API de mantenimiento de items)
-- Ejecutar como CORE_DEV ANTES del body (.pkb). Termina con "/" en linea aparte.
--
-- Control transaccional: el package NO hace COMMIT. Cada operacion de escritura abre un
-- SAVEPOINT propio y, si falla, hace ROLLBACK solo hasta ese savepoint (no toca el trabajo
-- previo del invocador) y relanza el error. Decide el invocador si confirma o revierte todo.
--
-- TABLA DE CODIGOS DE ERROR (rango propio -20100..-20199 negocio, -20900 tecnico)
--   -20100 e_catalogo_no_existe   El catalogo indicado no existe.
--                                 (insertar_item, listar_items)
--   -20101 e_item_no_existe       El item indicado no existe.
--                                 (actualizar_item, eliminar_item)
--   -20102 e_item_duplicado       El codigo ya existe dentro del catalogo.
--                                 (insertar_item)
--   -20103 e_nombre_obligatorio   El nombre del item es nulo o solo espacios.
--                                 (insertar_item, actualizar_item)
--   -20104 e_codigo_obligatorio   El codigo del item es nulo o solo espacios.
--                                 (insertar_item)
--   -20105 e_vigencia_invalida    Falta "desde" al insertar, o "hasta" es anterior a "desde".
--                                 (insertar_item, actualizar_item)
--   -20106 e_estado_invalido      El estado no es A ni I.
--                                 (insertar_item, actualizar_item)
--   -20107 e_catalogo_inactivo    El catalogo esta inactivo (I): no admite items nuevos.
--                                 (insertar_item)
--   -20900 e_error_tecnico        Error inesperado (no de negocio) envuelto con el error
--                                 original en el mensaje. (insertar_item, actualizar_item,
--                                 eliminar_item)
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_ttem_catalog AS
  c_estado_activo   CONSTANT CHAR(1) := 'A';
  c_estado_inactivo CONSTANT CHAR(1) := 'I';
  c_err_catalogo_no_existe  CONSTANT PLS_INTEGER := -20100;
  c_err_item_no_existe      CONSTANT PLS_INTEGER := -20101;
  c_err_item_duplicado      CONSTANT PLS_INTEGER := -20102;
  c_err_nombre_obligatorio  CONSTANT PLS_INTEGER := -20103;
  c_err_codigo_obligatorio  CONSTANT PLS_INTEGER := -20104;
  c_err_vigencia_invalida   CONSTANT PLS_INTEGER := -20105;
  c_err_estado_invalido     CONSTANT PLS_INTEGER := -20106;
  c_err_catalogo_inactivo   CONSTANT PLS_INTEGER := -20107;
  c_err_tecnico             CONSTANT PLS_INTEGER := -20900;
  e_catalogo_no_existe  EXCEPTION;
  e_item_no_existe      EXCEPTION;
  e_item_duplicado      EXCEPTION;
  e_nombre_obligatorio  EXCEPTION;
  e_codigo_obligatorio  EXCEPTION;
  e_vigencia_invalida   EXCEPTION;
  e_estado_invalido     EXCEPTION;
  e_catalogo_inactivo   EXCEPTION;
  e_error_tecnico       EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_catalogo_no_existe, -20100);
  PRAGMA EXCEPTION_INIT(e_item_no_existe,     -20101);
  PRAGMA EXCEPTION_INIT(e_item_duplicado,     -20102);
  PRAGMA EXCEPTION_INIT(e_nombre_obligatorio, -20103);
  PRAGMA EXCEPTION_INIT(e_codigo_obligatorio, -20104);
  PRAGMA EXCEPTION_INIT(e_vigencia_invalida,  -20105);
  PRAGMA EXCEPTION_INIT(e_estado_invalido,    -20106);
  PRAGMA EXCEPTION_INIT(e_catalogo_inactivo,  -20107);
  PRAGMA EXCEPTION_INIT(e_error_tecnico,      -20900);
  -- Inserta un item. Exige catalogo existente y ACTIVO. El codigo se normaliza (UPPER/TRIM) y el nombre (TRIM).
  -- p_item.item_id se ignora: el id sale de SEQ_TTEM_ITEM y se devuelve en p_item_id.
  PROCEDURE insertar_item (
    p_item     IN  typ_ttem_item,
    p_item_id  OUT ttem_item.item_id%TYPE);
  -- Actualiza nombre, valor, orden, estado y vigencia del item p_item.item_id.
  -- No permite cambiar el catalogo ni el codigo del item.
  PROCEDURE actualizar_item (
    p_item  IN typ_ttem_item);
  -- Eliminacion LOGICA: marca el item como inactivo (status = 'I'). Idempotente.
  PROCEDURE eliminar_item (
    p_item_id  IN ttem_item.item_id%TYPE);
  -- Devuelve los items de un catalogo ordenados por display_order y codigo.
  FUNCTION listar_items (
    p_catalog_id  IN ttem_catalog.catalog_id%TYPE)
    RETURN typ_ttem_item_tab;
END pkg_ttem_catalog;
/
