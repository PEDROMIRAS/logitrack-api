package com.pedromiras.logitrack;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.annotation.Transactional;

/**
 * Comprueba que Flyway aplica el esquema y que la base de datos
 * protege la máquina de estados (decisión D2).
 * Necesita un PostgreSQL accesible: docker compose up -d db
 */
@SpringBootTest
@Transactional // cada test hace rollback al terminar
class MigrationsTest {

    @Autowired
    JdbcClient jdbc;

    UUID userId;
    UUID shipmentId;

    @BeforeEach
    void creaUsuarioYEnvio() {
        // query(UUID.class): con Object.class JdbcClient devolvería un new Object() vacío, no el id
        userId = jdbc.sql("""
                INSERT INTO users (email, password_hash) VALUES ('test@logitrack.dev', 'x')
                RETURNING id""").query(UUID.class).single();

        shipmentId = jdbc.sql("""
                INSERT INTO shipments (tracking_code, sender_name, sender_address,
                    recipient_name, recipient_address, origin_city, destination_city,
                    weight_kg, created_by)
                VALUES ('LT-TEST0001', 'Remitente', 'Calle A 1', 'Destinatario', 'Calle B 2',
                    'Madrid', 'Valencia', 1.5, :user)
                RETURNING id""").param("user", userId).query(UUID.class).single();
    }

    @Test
    void cargaLasTransicionesPermitidas() {
        Integer total = jdbc.sql("SELECT count(*) FROM allowed_transitions")
                .query(Integer.class)
                .single();

        assertThat(total).isEqualTo(11);
    }

    @Test
    void aceptaUnaTransicionValida() {
        assertThat(insertaEvento("CREATED", "PICKED_UP")).isEqualTo(1);
    }

    @Test
    void rechazaUnaTransicionInvalida() {
        // el nombre importa: el servicio lo usará para traducir el error a 409 (D2)
        assertThatThrownBy(() -> insertaEvento("DELIVERED", "IN_TRANSIT"))
            .isInstanceOf(DataIntegrityViolationException.class)
            .hasMessageContaining("fk_events_transition");
    }

    @Test
    void rechazaUnEventoInicialQueNoEsCreated() {
        assertThatThrownBy(() -> jdbc.sql("""
                INSERT INTO shipment_events (shipment_id, from_status, to_status, occurred_at, recorded_by)
                VALUES (:shipment, NULL, 'IN_TRANSIT'::shipment_status, now(), :user)""")
                .param("shipment", shipmentId)
                .param("user", userId)
                .update())
            .isInstanceOf(DataIntegrityViolationException.class)
            .hasMessageContaining("ck_events_initial");
    }

    @Test
    void aceptaUnSoloEventoInicialPorEnvio() {
        assertThat(insertaEventoInicial()).isEqualTo(1);

        assertThatThrownBy(this::insertaEventoInicial)
            .isInstanceOf(DataIntegrityViolationException.class)
            .hasMessageContaining("uq_events_initial");
    }

    private int insertaEventoInicial() {
        return jdbc.sql("""
                INSERT INTO shipment_events (shipment_id, from_status, to_status, occurred_at, recorded_by)
                VALUES (:shipment, NULL, 'CREATED'::shipment_status, now(), :user)""")
                .param("shipment", shipmentId)
                .param("user", userId)
                .update();
    }

    private int insertaEvento(String desde, String hasta) {
        return jdbc.sql("""
                INSERT INTO shipment_events (shipment_id, from_status, to_status, occurred_at, recorded_by)
                VALUES (:shipment, :desde::shipment_status, :hasta::shipment_status, now(), :user)""")
                .param("shipment", shipmentId)
                .param("desde", desde)
                .param("hasta", hasta)
                .param("user", userId)
                .update();
    }
}
