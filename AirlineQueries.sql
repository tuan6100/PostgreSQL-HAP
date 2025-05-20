---- Đặt vé máy bay an toàn (với xử lý race condition)
CREATE OR REPLACE PROCEDURE book_ticket(
    _flight_id INT,
    _seat_id INT,
    _customer_id INT,
    _promotion_id INT DEFAULT NULL,
    OUT success BOOLEAN,
    OUT message TEXT,
    OUT order_id INT
) LANGUAGE plpgsql AS $$
DECLARE
    _seat_version INT;
    _is_available BOOLEAN;
    _ticket_id INT;
    _seat_class_id INT;
    _price NUMERIC;
    _discount_percent INT := 0;
    _airline_id INT;
    _max_tickets INT;
    _ticket_count INT;
BEGIN
    -- Bắt đầu giao dịch với REPEATABLE READ
    SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

    BEGIN
        -- Lấy thông tin về airline và max_tickets_per_order
        SELECT a.airline_id, a.max_tickets_per_order INTO _airline_id, _max_tickets
        FROM "Flight" f
                 JOIN "Aircraft" ac ON f.aircraft_id = ac.aircraft_id
                 JOIN "Airline" a ON ac.airline_id = a.airline_id
        WHERE f.flight_id = _flight_id;

        -- Kiểm tra số lượng vé đã đặt của khách hàng cho chuyến bay này
        SELECT COUNT(*) INTO _ticket_count
        FROM "Ticket" t
                 JOIN "BookedTicket" bt ON t.ticket_id = bt.ticket_id
        WHERE t.flight_id = _flight_id AND bt.customer_id = _customer_id;

        -- Kiểm tra giới hạn vé
        IF _max_tickets IS NOT NULL AND _ticket_count >= _max_tickets THEN
            success := false;
            message := 'Vượt quá số lượng vé tối đa cho phép';
            RETURN;
        END IF;

        -- Kiểm tra và khóa ghế với FOR UPDATE để ngăn trường hợp race condition
        SELECT s."version", s."is_available", s."seat_class_id"
        INTO _seat_version, _is_available, _seat_class_id
        FROM "Seat" s
        WHERE s."seat_id" = _seat_id
            FOR UPDATE;

        IF NOT FOUND THEN
            success := false;
            message := 'Không tìm thấy ghế';
            RETURN;
        END IF;

        IF NOT _is_available THEN
            success := false;
            message := 'Ghế đã được đặt';
            RETURN;
        END IF;

        -- Kiểm tra ghế có thuộc về máy bay của chuyến bay không
        IF NOT EXISTS (
            SELECT 1
            FROM "Flight" f
                     JOIN "Aircraft" ac ON f.aircraft_id = ac.aircraft_id
                     JOIN "Seat" s ON s.airline_id = ac.airline_id
            WHERE f.flight_id = _flight_id AND s.seat_id = _seat_id
        ) THEN
            success := false;
            message := 'Ghế không thuộc về chuyến bay này';
            RETURN;
        END IF;

        -- Lấy giá vé từ seat_class
        SELECT sc."price" INTO _price
        FROM "SeatClass" sc
        WHERE sc."seat_class_id" = _seat_class_id;

        -- Nếu có promotion, tính giảm giá
        IF _promotion_id IS NOT NULL THEN
            SELECT p."discount_percent" INTO _discount_percent
            FROM "Promotion" p
            WHERE p."promotion_id" = _promotion_id
              AND CURRENT_TIMESTAMP BETWEEN p."start_time" AND p."end_time";

            IF NOT FOUND THEN
                _discount_percent := 0;
            END IF;
        END IF;

        -- Cập nhật trạng thái ghế
        UPDATE "Seat"
        SET "is_available" = false,
            "version" = _seat_version + 1
        WHERE "seat_id" = _seat_id
          AND "version" = _seat_version;

        -- Nếu không cập nhật được, có nghĩa là đã bị người khác đặt
        IF NOT FOUND THEN
            success := false;
            message := 'Ghế đã được đặt bởi người khác trong quá trình xử lý';
            RETURN;
        END IF;

        -- Tạo đơn hàng mới
        INSERT INTO "TicketOrder" ("promotion_id", "total_price")
        VALUES (_promotion_id, _price * (100 - _discount_percent) / 100)
        RETURNING "order_id" INTO order_id;

        -- Tạo ticket mới
        INSERT INTO "Ticket" ("flight_id", "seat_id", "is_booked", "is_paid")
        VALUES (_flight_id, _seat_id, true, false)
        RETURNING "ticket_id" INTO _ticket_id;

        -- Liên kết ticket với customer và order
        INSERT INTO "BookedTicket" ("ticket_id", "customer_id", "order_id")
        VALUES (_ticket_id, _customer_id, order_id);

        -- Tạo hóa đơn
        INSERT INTO "Invoice" (
            "order_id",
            "paid_amount",
            "unpaid_amount",
            "issue_date"
        )
        VALUES (
                   order_id,
                   0,
                   _price * (100 - _discount_percent) / 100,
                   CURRENT_TIMESTAMP
               );

        success := true;
        message := 'Đặt vé thành công';

        -- Commit transaction
        COMMIT;
    EXCEPTION WHEN OTHERS THEN
        -- Rollback transaction khi có lỗi
        ROLLBACK;
        success := false;
        message := 'Lỗi: ' || SQLERRM;
        order_id := NULL;
    END;
END;
$$;


---- Giữ chỗ tạm thời (Hold Seat) với tính năng tự động giải phóng
CREATE OR REPLACE PROCEDURE hold_seat(
    p_seat_id INT,
    p_customer_id INT,
    p_hold_minutes INT DEFAULT 15,
    OUT success BOOLEAN,
    OUT message TEXT
) LANGUAGE plpgsql AS $$
DECLARE
    _is_available BOOLEAN;
    _seat_version INT;
BEGIN
    -- Bắt đầu giao dịch với REPEATABLE READ
    SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

    BEGIN
        -- Kiểm tra ghế có sẵn không
        SELECT "is_available", "version" INTO _is_available, _seat_version
        FROM "Seat"
        WHERE "seat_id" = p_seat_id
            FOR UPDATE;

        IF NOT FOUND THEN
            success := false;
            message := 'Không tìm thấy ghế';
            RETURN;
        END IF;

        IF NOT _is_available THEN
            success := false;
            message := 'Ghế đã được đặt hoặc đang được giữ bởi người khác';
            RETURN;
        END IF;

        -- Cập nhật trạng thái và thời gian giữ ghế
        UPDATE "Seat"
        SET
            "is_available" = false,
            "version" = _seat_version + 1,
            "hold_until" = CURRENT_TIMESTAMP + (p_hold_minutes || ' minutes')::INTERVAL
        WHERE "seat_id" = p_seat_id
          AND "version" = _seat_version;

        -- Kiểm tra cập nhật có thành công không
        IF NOT FOUND THEN
            success := false;
            message := 'Ghế đã bị thay đổi bởi người khác trong quá trình xử lý';
            RETURN;
        END IF;

        success := true;
        message := 'Đã giữ chỗ thành công, vui lòng hoàn tất đặt vé trong ' || p_hold_minutes || ' phút';

        -- Commit transaction
        COMMIT;
    EXCEPTION WHEN OTHERS THEN
        -- Rollback transaction khi có lỗi
        ROLLBACK;
        success := false;
        message := 'Lỗi: ' || SQLERRM;
    END;
END;
$$;

-- Function giải phóng các ghế đã quá thời gian giữ
CREATE OR REPLACE FUNCTION release_expired_seat_holds()
    RETURNS INTEGER AS $$
DECLARE
    released_count INTEGER;
BEGIN
    UPDATE "Seat"
    SET "is_available" = true,
        "hold_until" = NULL
    WHERE "hold_until" IS NOT NULL
      AND "hold_until" < CURRENT_TIMESTAMP;

    GET DIAGNOSTICS released_count = ROW_COUNT;
    RETURN released_count;
END;
$$ LANGUAGE plpgsql;


---- Sử dụng materialized view cho báo cáo và phân tích
CREATE MATERIALIZED VIEW flight_availability_summary AS
SELECT f.flight_id, f.departure_time,
       fr.departure_airport, fr.arrival_airport,
       COUNT(s.seat_id) AS total_seats,
       SUM(CASE WHEN s.is_available THEN 1 ELSE 0 END) AS available_seats
FROM "Flight" f
         JOIN "FlightRoute" fr ON f.route_id = fr.route_id
         JOIN "Aircraft" a ON f.aircraft_id = a.aircraft_id
         JOIN "Seat" s ON a.airline_id = s.airline_id
GROUP BY f.flight_id, f.departure_time, fr.departure_airport, fr.arrival_airport;