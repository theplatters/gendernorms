# Tests for the worker protocol of `DashboardRuntime`
# (`dashboard/src/runtime/protocol.jl`): message builders round-trip
# through `encode_message` and `decode_message`, non-finite metric
# values survive via `NONFINITE_TOKENS`, malformed messages are
# rejected with `ProtocolError`, and version mismatches are detected.

@testset "protocol" begin
    messages = [
        DR.handshake_message(string(UUIDs.uuid4())),
        DR.started_message(
            string(UUIDs.uuid4()),
            "run",
            "gender_norms",
            ["working_time_gap"],
            "2026-01-02T03:04:05",
            10,
        ),
        DR.rows_message([0, 1], Dict("working_time_gap" => [0.5, 0.75])),
        DR.finished_message(string(UUIDs.uuid4()), "success", "", 2, "2026-01-02T03:04:06"),
        DR.failed_message("boom", "setup"),
        DR.cancelled_message(string(UUIDs.uuid4())),
    ]

    @testset "encode/decode round-trip" begin
        for message in messages
            line = DR.encode_message(message)
            @test endswith(line, "\n")
            decoded = DR.decode_message(line)
            @test decoded["type"] == message["type"]
            for (key, value) in message
                key == "type" && continue
                @test decoded[key] == value
            end
        end
    end

    @testset "non-finite metric values survive via tokens" begin
        message = DR.rows_message(
            [0, 1, 2],
            Dict("working_time_gap" => [NaN, Inf, -Inf]),
        )
        line = DR.encode_message(message)
        @test occursin("\"NaN\"", line)
        @test occursin("\"Inf\"", line)
        decoded = DR.decode_message(line)
        values = decoded["metrics"]["working_time_gap"]
        @test isnan(values[1])
        @test values[2] === Inf
        @test values[3] === -Inf
        @test DR.encode_message(decoded) == line
    end

    @testset "malformed messages are rejected" begin
        @test_throws DR.ProtocolError DR.decode_message("not json at all")
        @test_throws DR.ProtocolError DR.decode_message("[1, 2, 3]")
        @test_throws DR.ProtocolError DR.decode_message("{}")
        @test_throws DR.ProtocolError DR.decode_message("{\"type\": \"bogus\"}")
        @test_throws DR.ProtocolError DR.decode_message("{\"type\": \"rows\", \"ticks\": [0]}")
        @test_throws DR.ProtocolError DR.decode_message(
            "{\"type\": \"rows\", \"ticks\": [\"a\"], \"metrics\": {}}",
        )
        @test_throws DR.ProtocolError DR.decode_message(
            "{\"type\": \"rows\", \"ticks\": [0, 1], \"metrics\": {\"m\": [0.5]}}",
        )
        @test_throws DR.ProtocolError DR.decode_message(
            "{\"type\": \"failed\", \"error\": \"e\", \"stage\": 3}",
        )
        @test_throws DR.ProtocolError DR.decode_message(
            "{\"type\": \"cancelled\", \"run_id\": \"x\", \"extra\": 1}",
        )
        @test_throws DR.ProtocolError DR.decode_message(
            "{\"type\": \"finished\", \"run_id\": \"x\", \"outcome\": \"maybe\", \"error\": \"\", \"ticks_executed\": 0, \"finished_at\": \"t\"}",
        )
    end

    @testset "malformed problems are reported clearly" begin
        try
            DR.decode_message("{\"type\": \"started\", \"run_id\": 1, \"surplus\": 2}")
            @test false
        catch err
            @test err isa DR.ProtocolError
            @test any(problem -> occursin("unknown key", problem), err.problems)
            @test any(problem -> occursin("missing required key \"name\"", problem), err.problems)
            @test any(problem -> occursin("[started] key \"run_id\"", problem), err.problems)
        end
    end

    @testset "version mismatch is rejected" begin
        message = DR.handshake_message(string(UUIDs.uuid4()))
        message["protocol_version"] = DR.PROTOCOL_VERSION + 1
        try
            DR.decode_message(DR.encode_message(message))
            @test false
        catch err
            @test err isa DR.ProtocolError
            @test any(
                problem -> occursin("protocol version mismatch", problem),
                err.problems,
            )
        end
        @test_throws DR.ProtocolError DR.encode_message(message)
    end
end
