SELECT pg_read_file('/etc/hostname') AS hostname;

CREATE OR REPLACE PROCEDURE book_ticket(
    p_flight_id INT,
    p_seat_id INT,
    p_customer_id INT,
    OUT success BOOLEAN,
    OUT message TEXT,
    OUT p_order_id INT,
    p_promotion_id INT DEFAULT NULL  -- Tham số DEFAULT cuối cùng
) LANGUAGE plpgsql AS $$
DECLARE
    v_seat_version INT;
    v_is_available BOOLEAN;
    v_ticket_id INT;
    v_seat_class_id INT;
    v_price NUMERIC;
    v_discount_percent INT := 0;
    v_airline_id INT;
    v_max_tickets INT;
    v_ticket_count INT;
    v_hold_until TIMESTAMP;
    v_invoice_id INT;
    v_total_amount BIGINT;
    v_flight_departure_time TIMESTAMP;
BEGIN
    SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

    BEGIN
        SELECT ac.airline_id, a.max_tickets_per_order, f.departure_time
        INTO v_airline_id, v_max_tickets, v_flight_departure_time
        FROM "Flight" f
                 JOIN "Aircraft" ac ON f.aircraft_id = ac.aircraft_id
                 JOIN "Airline" a ON ac.airline_id = a.airline_id
        WHERE f.flight_id = p_flight_id
          AND f.departure_time IS NOT NULL;

        IF NOT FOUND THEN
            success := false;
            message := 'Flight not found';
            RETURN;
        END IF;

        SELECT COUNT(*) INTO v_ticket_count
        FROM "Ticket" t
                 JOIN "BookedTicket" bt ON t.ticket_id = bt.ticket_id
                 JOIN "TicketOrder" ord ON bt.order_id = ord.order_id
        WHERE t.flight_id = p_flight_id AND ord.customer_id = p_customer_id;

        IF v_max_tickets IS NOT NULL AND v_ticket_count >= v_max_tickets THEN
            success := false;
            message := 'Exceeded maximum number of tickets allowed per customer';
            RETURN;
        END IF;

        SELECT s."version", s."is_available", s."seat_class_id", s."hold_until"
        INTO v_seat_version, v_is_available, v_seat_class_id, v_hold_until
        FROM "Seat" s
        WHERE s."seat_id" = p_seat_id
            FOR UPDATE;

        IF NOT FOUND THEN
            success := false;
            message := 'Seat not found';
            RETURN;
        END IF;

        IF NOT v_is_available AND (v_hold_until IS NULL OR v_hold_until > CURRENT_TIMESTAMP) THEN
            success := false;
            message := 'Seat is not available or being held by someone else';
            RETURN;
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM "Flight" f
                     JOIN "Aircraft" ac ON f.aircraft_id = ac.aircraft_id
                     JOIN "Seat" s ON s.aircraft_id = ac.aircraft_id  -- Đúng reference
            WHERE f.flight_id = p_flight_id AND s.seat_id = p_seat_id
        ) THEN
            success := false;
            message := 'Seat does not belong to this flight';
            RETURN;
        END IF;

        SELECT sc.price INTO v_price
        FROM "SeatClass" sc
        WHERE sc.seat_class_id = v_seat_class_id;

        IF NOT FOUND THEN
            success := false;
            message := 'Seat class not found';
            RETURN;
        END IF;

        IF p_promotion_id IS NOT NULL THEN
            SELECT discount_percent INTO v_discount_percent
            FROM "Voucher"
            WHERE voucher_id = p_promotion_id
              AND start_time <= CURRENT_TIMESTAMP
              AND end_time >= CURRENT_TIMESTAMP;

            IF NOT FOUND THEN
                success := false;
                message := 'Invalid or expired voucher';
                RETURN;
            END IF;
        END IF;

        v_total_amount := v_price * (100 - v_discount_percent) / 100;

        INSERT INTO "TicketOrder" ("customer_id", "promotion_id")
        VALUES (p_customer_id, p_promotion_id)
        RETURNING order_id INTO p_order_id;

        INSERT INTO "Ticket" (
            "ticket_code",
            "flight_id",
            "flight_departure_time",
            "seat_id",
            "created_at",
            "status"
        )
        VALUES (
                   gen_random_uuid(),
                   p_flight_id,
                   v_flight_departure_time,
                   p_seat_id,
                   CURRENT_TIMESTAMP,
                   1
               )
        RETURNING ticket_id INTO v_ticket_id;

        INSERT INTO "BookedTicket" ("ticket_id", "order_id")
        VALUES (v_ticket_id, p_order_id);

        UPDATE "Seat"
        SET "is_available" = false,
            "version" = v_seat_version + 1,
            "hold_until" = NULL
        WHERE "seat_id" = p_seat_id
          AND "version" = v_seat_version;
        IF NOT FOUND THEN
            success := false;
            message := 'Seat was modified by another transaction';
            RETURN;
        END IF;

        INSERT INTO "Invoice" ("order_id", "total_amount", "issue_date")
        VALUES (p_order_id, v_total_amount, CURRENT_TIMESTAMP)
        RETURNING invoice_id INTO v_invoice_id;

        INSERT INTO "Payment" ("invoice_id", "amount", "payment_date", "payment_method")
        VALUES (v_invoice_id, v_total_amount, CURRENT_TIMESTAMP, 'Credit Card');

        success := true;
        message := 'Ticket booked successfully. Order ID: ' || p_order_id;

        COMMIT;

    EXCEPTION WHEN OTHERS THEN
        ROLLBACK;
        success := false;
        message := 'Booking failed: ' || SQLERRM;
    END;
END;
$$;


CREATE OR REPLACE PROCEDURE hold_seat(
    p_seat_id INT,
    p_customer_id INT,
    OUT success BOOLEAN,
    OUT message TEXT,
    p_hold_minutes INT DEFAULT 15
) LANGUAGE plpgsql AS $$
DECLARE
    v_is_available BOOLEAN;
    v_seat_version INT;
    v_hold_until TIMESTAMP;
BEGIN
    SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

    BEGIN
        SELECT "is_available", "version", "hold_until"
        INTO v_is_available, v_seat_version, v_hold_until
        FROM "Seat"
        WHERE "seat_id" = p_seat_id
            FOR UPDATE;

        IF NOT FOUND THEN
            success := false;
            message := 'Seat not found';
            RETURN;
        END IF;

        IF NOT v_is_available AND (v_hold_until IS NULL OR v_hold_until > CURRENT_TIMESTAMP) THEN
            success := false;
            message := 'Seat is not available or being held by someone else';
            RETURN;
        END IF;

        UPDATE "Seat"
        SET "is_available" = false,
            "version" = v_seat_version + 1,
            "hold_until" = CURRENT_TIMESTAMP + (p_hold_minutes || ' minutes')::INTERVAL
        WHERE "seat_id" = p_seat_id
          AND "version" = v_seat_version;

        IF NOT FOUND THEN
            success := false;
            message := 'Seat was modified by another transaction';
            RETURN;
        END IF;

        success := true;
        message := 'Seat held successfully. Please complete booking within ' || p_hold_minutes || ' minutes';

        COMMIT;

    EXCEPTION WHEN OTHERS THEN
        ROLLBACK;
        success := false;
        message := 'Hold failed: ' || SQLERRM;
    END;
END;
$$;

CREATE OR REPLACE FUNCTION release_expired_seat_holds()
    RETURNS INTEGER AS $$
DECLARE
    released_count INTEGER;
BEGIN
    UPDATE "Seat"
    SET "is_available" = true,
        "hold_until" = NULL,
        "version" = "version" + 1
    WHERE "hold_until" IS NOT NULL
      AND "hold_until" < CURRENT_TIMESTAMP;

    GET DIAGNOSTICS released_count = ROW_COUNT;
    RETURN released_count;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE PROCEDURE cancel_booking(
    p_order_id INT,
    p_customer_id INT,
    OUT success BOOLEAN,
    OUT message TEXT
) LANGUAGE plpgsql AS $$
DECLARE
    v_ticket_record RECORD;
BEGIN
    SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM "TicketOrder"
            WHERE order_id = p_order_id AND customer_id = p_customer_id
        ) THEN
            success := false;
            message := 'Order not found or does not belong to customer';
            RETURN;
        END IF;
        FOR v_ticket_record IN
            SELECT t.seat_id
            FROM "Ticket" t
                     JOIN "BookedTicket" bt ON t.ticket_id = bt.ticket_id
            WHERE bt.order_id = p_order_id
            LOOP
                UPDATE "Seat"
                SET "is_available" = true,
                    "hold_until" = NULL,
                    "version" = "version" + 1
                WHERE "seat_id" = v_ticket_record.seat_id;
            END LOOP;
        UPDATE "Ticket"
        SET "status" = -1
        WHERE ticket_id IN (
            SELECT bt.ticket_id
            FROM "BookedTicket" bt
            WHERE bt.order_id = p_order_id
        );
        success := true;
        message := 'Booking cancelled successfully';
        COMMIT;
    EXCEPTION WHEN OTHERS THEN
        ROLLBACK;
        success := false;
        message := 'Cancellation failed: ' || SQLERRM;
    END;
END;
$$;



CREATE MATERIALIZED VIEW flight_availability_summary AS
SELECT f.flight_id, f.departure_time,
       fr.departure_airport, fr.arrival_airport,
       COUNT(s.seat_id) AS total_seats,
       SUM(CASE WHEN s.is_available THEN 1 ELSE 0 END) AS available_seats
FROM "Flight" f
        JOIN "FlightRoute" fr ON f.route_id = fr.route_id
        JOIN "Aircraft" a ON f.aircraft_id = a.aircraft_id
        JOIN "Seat" s ON a.aircraft_id = s.aircraft_id
GROUP BY f.flight_id, f.departure_time, fr.departure_airport, fr.arrival_airport;