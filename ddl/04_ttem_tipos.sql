-- =====================================================================
-- A.2 - Object Type y coleccion SQL para la API del package
-- Ejecutar como CORE_DEV. Cada bloque termina con "/" en linea aparte.
-- =====================================================================
CREATE OR REPLACE TYPE typ_ttem_item AS OBJECT (
  item_id        NUMBER(10),
  catalog_id     NUMBER(10),
  item_code      VARCHAR2(30),
  item_name      VARCHAR2(200),
  item_value     VARCHAR2(200),
  display_order  NUMBER(5),
  status         CHAR(1),
  valid_from     DATE,
  valid_to       DATE
);
/
CREATE OR REPLACE TYPE typ_ttem_item_tab AS TABLE OF typ_ttem_item;
/
