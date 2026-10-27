-- =====================================================================
-- A.5 - Tabla de rechazos de la carga masiva desde TTEM_ITEM_STG
-- Ejecutar como CORE_DEV, despues de 01_ttem_tablas.sql. Sin lineas en blanco dentro de las sentencias.
-- Una fila por registro de staging rechazado: stg_id, codigo de motivo y mensaje.
-- La FK apunta a TTEM_ITEM_STG (tabla del contrato externo) sin modificarla.
-- =====================================================================
CREATE SEQUENCE seq_ttem_load_error START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE TABLE ttem_load_error (
  load_error_id  NUMBER(10)     NOT NULL,
  stg_id         NUMBER(10)     NOT NULL,
  load_batch     VARCHAR2(20)   NOT NULL,
  error_code     VARCHAR2(30)   NOT NULL,
  error_message  VARCHAR2(400)  NOT NULL,
  created_by     VARCHAR2(128)  DEFAULT SYS_CONTEXT('USERENV', 'SESSION_USER') NOT NULL,
  created_at     DATE           DEFAULT SYSDATE NOT NULL,
  CONSTRAINT pk_ttem_load_error PRIMARY KEY (load_error_id),
  CONSTRAINT fk_ttem_load_error_ttem_item_stg FOREIGN KEY (stg_id)
    REFERENCES ttem_item_stg (stg_id)
);
CREATE INDEX ix_ttem_load_error_stg_id ON ttem_load_error (stg_id);
