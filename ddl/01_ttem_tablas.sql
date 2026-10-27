-- =====================================================================
-- A.1 - Modelo de catalogos: secuencias, tablas y constraints
-- Ejecutar como CORE_DEV, despues de los scripts de setup/.
-- Nomenclatura segun Anexo C. NOTA: sin lineas en blanco dentro de las sentencias.
-- =====================================================================

CREATE SEQUENCE seq_ttem_catalog START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_ttem_item    START WITH 1 INCREMENT BY 1 NOCACHE;

CREATE TABLE ttem_catalog (
  catalog_id    NUMBER(10)     NOT NULL,
  catalog_code  VARCHAR2(30)   NOT NULL,
  catalog_name  VARCHAR2(100)  NOT NULL,
  description   VARCHAR2(400),
  status        CHAR(1)        DEFAULT 'A' NOT NULL,
  created_by    VARCHAR2(128)  NOT NULL,
  created_at    DATE           NOT NULL,
  updated_by    VARCHAR2(128)  NOT NULL,
  updated_at    DATE           NOT NULL,
  CONSTRAINT pk_ttem_catalog PRIMARY KEY (catalog_id),
  CONSTRAINT uk_ttem_catalog_code UNIQUE (catalog_code),
  CONSTRAINT ck_ttem_catalog_status CHECK (status IN ('A', 'I')),
  CONSTRAINT ck_ttem_catalog_code CHECK (catalog_code = UPPER(TRIM(catalog_code)))
);

CREATE TABLE ttem_item (
  item_id        NUMBER(10)     NOT NULL,
  catalog_id     NUMBER(10)     NOT NULL,
  item_code      VARCHAR2(30)   NOT NULL,
  item_name      VARCHAR2(200)  NOT NULL,
  item_value     VARCHAR2(200),
  display_order  NUMBER(5)      DEFAULT 0 NOT NULL,
  status         CHAR(1)        DEFAULT 'A' NOT NULL,
  valid_from     DATE           NOT NULL,
  valid_to       DATE,
  created_by     VARCHAR2(128)  NOT NULL,
  created_at     DATE           NOT NULL,
  updated_by     VARCHAR2(128)  NOT NULL,
  updated_at     DATE           NOT NULL,
  CONSTRAINT pk_ttem_item PRIMARY KEY (item_id),
  CONSTRAINT fk_ttem_item_ttem_catalog FOREIGN KEY (catalog_id)
    REFERENCES ttem_catalog (catalog_id),
  CONSTRAINT uk_ttem_item_catalog_code UNIQUE (catalog_id, item_code),
  CONSTRAINT ck_ttem_item_status CHECK (status IN ('A', 'I')),
  CONSTRAINT ck_ttem_item_code CHECK (item_code = UPPER(TRIM(item_code))),
  CONSTRAINT ck_ttem_item_valid_to CHECK (valid_to IS NULL OR valid_to >= valid_from)
);
