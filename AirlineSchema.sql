
CREATE TABLE "Country" (
          "country_id" SERIAL PRIMARY KEY,
          "country_name" VARCHAR UNIQUE NOT NULL,
          "abbreviation" VARCHAR(2) UNIQUE NOT NULL,
          "continent" VARCHAR NOT NULL,
          "gmt" INTEGER NOT NULL
);

CREATE TABLE "City" (
       "city_id" SERIAL PRIMARY KEY,
       "city_name" VARCHAR UNIQUE NOT NULL,
       "country_id" INTEGER NOT NULL REFERENCES "Country" ("country_id")
);

CREATE TABLE "Airline" (
          "airline_id" SERIAL PRIMARY KEY,
          "airline_name" VARCHAR UNIQUE NOT NULL,
          "city_id" INTEGER NOT NULL REFERENCES "City" ("city_id"),
          "address" VARCHAR NOT NULL,
          "website" VARCHAR NOT NULL,
          "max_tickets_per_order" INTEGER
);

CREATE TABLE "Airport" (
          "airport_id" SERIAL PRIMARY KEY,
          "airport_name" VARCHAR UNIQUE NOT NULL,
          "city_id" INTEGER NOT NULL REFERENCES "City" ("city_id"),
          "address" VARCHAR NOT NULL
);

CREATE TABLE "Aircraft" (
           "aircraft_id" SERIAL PRIMARY KEY,
           "aircraft_name" VARCHAR UNIQUE NOT NULL,
           "airline_id" INTEGER NOT NULL REFERENCES "Airline" ("airline_id"),
           "seat_count" INTEGER NOT NULL
);

CREATE TABLE "SeatClass" (
            "seat_class_id" SERIAL PRIMARY KEY,
            "seat_class_name" VARCHAR UNIQUE NOT NULL,
            "airline_id" INTEGER NOT NULL REFERENCES "Airline" ("airline_id"),
            "price" INTEGER NOT NULL CHECK ("price" >= 0)
);

CREATE TABLE "Voucher" (
          "voucher_id" SERIAL PRIMARY KEY,
          "voucher_name" VARCHAR UNIQUE NOT NULL,
          "discount_percent" INTEGER NOT NULL DEFAULT 0 CHECK ("discount_percent" BETWEEN 0 AND 100),
          "amount" INTEGER NOT NULL CHECK ("amount" >= 0),
          "start_time" TIMESTAMP NOT NULL,
          "end_time" TIMESTAMP NOT NULL CHECK ("end_time" > "start_time")
);

CREATE TABLE "TicketOrder" (
              "order_id" SERIAL PRIMARY KEY,
              "customer_id" INTEGER REFERENCES "Customer" ("customer_id"),
              "promotion_id" INTEGER REFERENCES "Voucher" ("voucher_id")
);

CREATE TABLE "Seat" (
       "seat_id" SERIAL PRIMARY KEY,
       "seat_class_id" INTEGER NOT NULL REFERENCES "SeatClass" ("seat_class_id"),
       "aircraft_id" INTEGER NOT NULL REFERENCES "Aircraft" ("aircraft_id"),
       "seat_code" VARCHAR NOT NULL,
       "is_available" BOOLEAN DEFAULT TRUE,
       "hold_until" TIMESTAMP,
       "version" INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX idx_seat_availability ON "Seat" ("is_available");
CREATE INDEX idx_hold_util ON "Seat" ("hold_until");

CREATE TABLE "FlightRoute" (
              "route_id" SERIAL PRIMARY KEY,
              "departure_airport" INTEGER NOT NULL REFERENCES "Airport" ("airport_id"),
              "arrival_airport" INTEGER NOT NULL REFERENCES "Airport" ("airport_id")
);
CREATE INDEX idx_flight_route_airports ON "FlightRoute" ("departure_airport", "arrival_airport");

CREATE TABLE "Flight" (
                          "flight_id" SERIAL,
                          "route_id" INTEGER NOT NULL REFERENCES "FlightRoute" ("route_id"),
                          "aircraft_id" INTEGER NOT NULL REFERENCES "Aircraft" ("aircraft_id"),
                          "departure_time" TIMESTAMP NOT NULL,
                          "estimated_flight_duration" TIME,
                          PRIMARY KEY ("flight_id", "departure_time")
) PARTITION BY RANGE ("departure_time");


CREATE OR REPLACE PROCEDURE create_monthly_flight_partitions(
    start_date DATE,
    end_date DATE
) LANGUAGE plpgsql AS $$
DECLARE
    current_date_var DATE := start_date;
    next_date DATE;
    partition_name TEXT;
    sql_command TEXT;
BEGIN
    WHILE current_date_var <= end_date LOOP
            next_date := current_date_var + INTERVAL '1 month';
            partition_name := 'Flight_' || TO_CHAR(current_date_var, 'YYYYMM');
            sql_command := 'CREATE TABLE IF NOT EXISTS "' || partition_name || '" PARTITION OF "Flight" ' ||
                           'FOR VALUES FROM (''' || current_date_var || ' 00:00:00'') TO (''' || next_date || ' 00:00:00'');';
            EXECUTE sql_command;
            current_date_var := next_date;
        END LOOP;
END;
$$;

CALL create_monthly_flight_partitions(
                CURRENT_DATE,
                (CURRENT_DATE + INTERVAL '12 months')::DATE
);

CREATE INDEX idx_flight_route_id ON "Flight" ("route_id");
CREATE INDEX idx_flight_departure_time ON "Flight" ("departure_time", "estimated_flight_duration");

CREATE TABLE "Customer" (
           "customer_id" SERIAL PRIMARY KEY,
           "country_id" INTEGER REFERENCES "Country" ("country_id"),
           "full_name" VARCHAR NOT NULL,
           "gender" VARCHAR(1) NOT NULL CHECK ("gender" IN ('M', 'F')),
           "email" VARCHAR
);

CREATE INDEX idx_customer_info ON "Customer" ("full_name");

CREATE TABLE "Customer_Auth" (
                "customer_id" INTEGER REFERENCES "Customer" ("customer_id"),
                "phone_number" VARCHAR(10) NOT NULL,
                "password" VARCHAR UNIQUE NOT NULL,
                PRIMARY KEY ("customer_id")
);

CREATE TABLE "Ticket" (
         "ticket_id" SERIAL PRIMARY KEY,
         "ticket_code" UUID UNIQUE,
         "flight_id" INTEGER NOT NULL,
         "flight_departure_time" TIMESTAMP ,
         "seat_id" INTEGER NOT NULL REFERENCES "Seat" ("seat_id"),
         "created_at" TIMESTAMP NOT NULL,
         "status" INTEGER DEFAULT 0,
         FOREIGN KEY ("flight_id", "flight_departure_time") REFERENCES "Flight" ("flight_id", "departure_time")
);

CREATE TABLE "BookedTicket" (
               "ticket_id" INTEGER REFERENCES "Ticket" ("ticket_id"),
               "order_id" INTEGER NOT NULL REFERENCES "TicketOrder" ("order_id"),
               PRIMARY KEY ("ticket_id")
);

CREATE TABLE "Invoice" (
          "invoice_id" SERIAL PRIMARY KEY,
          "order_id" INTEGER NOT NULL REFERENCES "TicketOrder" ("order_id"),
          "total_amount" BIGINT NOT NULL DEFAULT 0,
          "issue_date" TIMESTAMP NOT NULL
);

CREATE TABLE "Payment" (
          "payment_id" SERIAL PRIMARY KEY,
          "invoice_id" INTEGER NOT NULL REFERENCES "Invoice" ("invoice_id"),
          "amount" BIGINT NOT NULL,
          "payment_date" TIMESTAMP NOT NULL,
          "payment_method" VARCHAR NOT NULL
);