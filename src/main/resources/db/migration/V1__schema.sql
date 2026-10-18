-- LogiTrack · esquema inicial
-- Decisiones referenciadas (D1–D6) en docs/diseno.md

CREATE TYPE user_role       AS ENUM ('ADMIN', 'OPERATOR');
CREATE TYPE shipment_status AS ENUM (
  'CREATED', 'PICKED_UP', 'IN_TRANSIT', 'OUT_FOR_DELIVERY',
  'DELIVERED', 'INCIDENT', 'RETURNED', 'CANCELLED'
);
CREATE TYPE delivery_status AS ENUM ('PENDING', 'SENT', 'FAILED');

CREATE TABLE users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email         VARCHAR(255) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  role          user_role    NOT NULL DEFAULT 'OPERATOR',
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- D2: la base de datos solo acepta transiciones listadas aquí
CREATE TABLE allowed_transitions (
  from_status shipment_status NOT NULL,
  to_status   shipment_status NOT NULL,
  PRIMARY KEY (from_status, to_status)
);

CREATE TABLE shipments (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tracking_code     VARCHAR(20)     NOT NULL UNIQUE,
  status            shipment_status NOT NULL DEFAULT 'CREATED',  -- D1: estado cacheado
  sender_name       VARCHAR(120)    NOT NULL,
  sender_address    TEXT            NOT NULL,
  recipient_name    VARCHAR(120)    NOT NULL,
  recipient_address TEXT            NOT NULL,
  recipient_email   VARCHAR(255),
  origin_city       VARCHAR(80)     NOT NULL,
  destination_city  VARCHAR(80)     NOT NULL,
  weight_kg         NUMERIC(8,3)    NOT NULL CHECK (weight_kg > 0),
  created_by        UUID            NOT NULL REFERENCES users(id),
  created_at        TIMESTAMPTZ     NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ     NOT NULL DEFAULT now(),
  delivered_at      TIMESTAMPTZ
);

-- D1: historial append-only
CREATE TABLE shipment_events (
  id          BIGSERIAL PRIMARY KEY,
  shipment_id UUID            NOT NULL REFERENCES shipments(id),
  from_status shipment_status,                          -- NULL solo en el evento inicial
  to_status   shipment_status NOT NULL,
  location    VARCHAR(120),
  note        TEXT,
  occurred_at TIMESTAMPTZ     NOT NULL,                 -- cuándo pasó en el mundo real
  recorded_by UUID            NOT NULL REFERENCES users(id),
  created_at  TIMESTAMPTZ     NOT NULL DEFAULT now(),   -- cuándo se registró
  -- con from_status NULL la FK no se comprueba (MATCH SIMPLE), de ahí el CHECK
  CONSTRAINT fk_events_transition FOREIGN KEY (from_status, to_status)
    REFERENCES allowed_transitions (from_status, to_status),
  CONSTRAINT ck_events_initial CHECK (from_status IS NOT NULL OR to_status = 'CREATED')
);

CREATE TABLE webhook_subscriptions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  url         TEXT              NOT NULL,
  secret      VARCHAR(64)       NOT NULL,               -- firma HMAC-SHA256
  event_types shipment_status[] NOT NULL,
  active      BOOLEAN           NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ       NOT NULL DEFAULT now()
);

-- D3: outbox de webhooks
CREATE TABLE webhook_deliveries (
  id              BIGSERIAL PRIMARY KEY,
  subscription_id UUID            NOT NULL REFERENCES webhook_subscriptions(id),
  event_id        BIGINT          NOT NULL REFERENCES shipment_events(id),
  payload         JSONB           NOT NULL,
  status          delivery_status NOT NULL DEFAULT 'PENDING',
  attempts        SMALLINT        NOT NULL DEFAULT 0,
  next_attempt_at TIMESTAMPTZ     NOT NULL DEFAULT now(),
  last_error      TEXT,
  created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
  CONSTRAINT uq_delivery UNIQUE (subscription_id, event_id)
);

CREATE INDEX idx_shipments_status_created ON shipments (status, created_at DESC);
CREATE INDEX idx_events_shipment_time     ON shipment_events (shipment_id, occurred_at);
CREATE INDEX idx_deliveries_pending       ON webhook_deliveries (next_attempt_at)
  WHERE status = 'PENDING';
