# Tests for live metric streaming of `DashboardRuntime`
# (`dashboard/src/runtime/live_logger.jl`): the buffer rows published
# during a real `GenderNorms.run` exactly match a plain run of the same
# spec and seed, callbacks never block when the consumer is delayed,
# over-capacity rows are dropped, and the `StreamWriter` batches rows
# into ordered protocol messages.

@testset "live logger" begin
    function plain_result(spec)
        return GN.run(GN.create_world(spec))
    end

    function live_result(spec, logger)
        world = GN.create_world(spec)
        GN.add_logger!(world, logger)
        return GN.run(world)
    end

    function make_info(spec)
        return GN.RunInfo(
            string(UUIDs.uuid4()),
            spec.name,
            spec.model_name,
            spec,
            Dict{String, Any}(),
            sort!(copy(spec.logging.metrics)),
            Dates.now(),
        )
    end

    function decode_stream(stream)
        return [
            DR.decode_message(line) for
                line in split(String(take!(stream)), "\n") if !isempty(strip(line))
        ]
    end

    function buffer_view(logger)
        rows = DR.published_rows(logger.buffer)
        ticks = logger.buffer.ticks[1:rows]
        metrics = Dict{String, Vector{Float64}}(
            name => values[1:rows] for (name, values) in
                zip(logger.buffer.names, logger.buffer.columns)
        )
        return ticks, metrics
    end

    @testset "published rows match a plain run exactly" begin
        spec = tiny_spec(ticks = 4, agents_per_gender = 5, seed = 3)
        logger = DR.LiveLogger(sort!(copy(spec.logging.metrics)), spec.runtime.ticks)
        streamed = live_result(spec, logger)
        reference = plain_result(spec)
        @test streamed.ticks == reference.ticks
        @test streamed.metrics == reference.metrics
        ticks, metrics = buffer_view(logger)
        @test ticks == reference.ticks
        @test metrics == reference.metrics
        @test DR.published_rows(logger.buffer) == reference.ticks_executed
        @test logger.info !== nothing
        @test logger.finished !== nothing
    end

    @testset "callbacks never block on a delayed consumer" begin
        spec = tiny_spec(ticks = 20, agents_per_gender = 10, seed = 4)
        logger = DR.LiveLogger(sort!(copy(spec.logging.metrics)), spec.runtime.ticks)
        consumer = @async begin
            sleep(2.0)
            DR.published_rows(logger.buffer)
        end
        result = live_result(spec, logger)
        @test GN.is_success(result)
        @test fetch(consumer) == result.ticks_executed
        ticks, metrics = buffer_view(logger)
        reference = plain_result(spec)
        @test ticks == reference.ticks
        @test metrics == reference.metrics
    end

    @testset "rows beyond the budget are dropped, never blocking" begin
        logger = DR.LiveLogger(["value"], 2)
        for tick in 1:5
            GN.metrics_recorded!(logger, tick, Dict{String, Float64}("value" => Float64(tick)))
        end
        @test DR.published_rows(logger.buffer) == 2
        ticks, metrics = buffer_view(logger)
        @test ticks == [1, 2]
        @test metrics["value"] == [1.0, 2.0]
    end

    @testset "stream writer batches rows after the start message" begin
        spec = tiny_spec(ticks = 5, agents_per_gender = 5, seed = 6)
        logger = DR.LiveLogger(sort!(copy(spec.logging.metrics)), spec.runtime.ticks)
        stream = IOBuffer()
        writer = DR.StreamWriter(stream, logger; batch_size = 2, poll_interval = 0.01)
        DR.start_stream(writer)
        world = GN.create_world(spec)
        GN.add_logger!(world, logger)
        result = GN.run(world)
        @test DR.finish_stream!(writer) >= 0

        messages = [DR.decode_message(line) for line in split(String(take!(stream)), "\n") if !isempty(strip(line))]
        @test messages[1]["type"] == "started"
        @test messages[1]["run_id"] == result.id
        @test messages[1]["metric_names"] == sort!(copy(spec.logging.metrics))
        rows = filter(message -> message["type"] == "rows", messages)
        @test !isempty(rows)
        @test all(message -> length(message["ticks"]) <= 2, rows)
        ticks = vcat((message["ticks"] for message in rows)...)
        metrics = Dict{String, Vector{Float64}}(
            name => vcat((message["metrics"][name] for message in rows)...) for
                name in spec.logging.metrics
        )
        @test ticks == result.ticks
        @test metrics == result.metrics
    end

    @testset "metric buffer preallocates sorted columns" begin
        buffer = DR.MetricBuffer(["b", "a"], 3)
        @test buffer.names == ["a", "b"]
        @test length(buffer.ticks) == 3
        @test all(column -> length(column) == 3, buffer.columns)
        @test DR.published_rows(buffer) == 0
    end

    @testset "rows never overtake a pending start message" begin
        spec = tiny_spec(ticks = 5, agents_per_gender = 5, seed = 8)
        logger = DR.LiveLogger(sort!(copy(spec.logging.metrics)), spec.runtime.ticks)
        info = make_info(spec)
        stream = IOBuffer()
        writer = DR.StreamWriter(stream, logger; batch_size = 2, poll_interval = 0.01)
        GN.run_started!(logger, info)
        for tick in 1:5
            GN.metrics_recorded!(
                logger,
                tick,
                Dict{String, Float64}(name => Float64(tick) for name in logger.buffer.names),
            )
        end
        # Run the row phase before any lifecycle drain: the exact window
        # in which the producer can win the race. `started` must still
        # lead every `rows` message.
        @test DR.stream_rows!(writer) == 5
        messages = decode_stream(stream)
        @test [message["type"] for message in messages] == ["started", "rows", "rows", "rows"]
        @test messages[1]["run_id"] == info.id
        @test DR.finish_stream!(writer) == 0
        @test isempty(decode_stream(stream))
    end

    @testset "a row-less run still emits started before the end" begin
        spec = tiny_spec(ticks = 2, agents_per_gender = 5, seed = 9)
        logger = DR.LiveLogger(sort!(copy(spec.logging.metrics)), spec.runtime.ticks)
        info = make_info(spec)
        stream = IOBuffer()
        writer = DR.StreamWriter(stream, logger; batch_size = 2, poll_interval = 0.01)
        GN.run_started!(logger, info)
        @test DR.finish_stream!(writer) == 0
        messages = decode_stream(stream)
        @test [message["type"] for message in messages] == ["started"]
    end

    @testset "started strictly precedes rows for a racing writer" begin
        for trial in 1:10
            spec = tiny_spec(ticks = 12, agents_per_gender = 5, seed = trial)
            logger = DR.LiveLogger(sort!(copy(spec.logging.metrics)), spec.runtime.ticks)
            stream = IOBuffer()
            writer = DR.StreamWriter(stream, logger; batch_size = 3, poll_interval = 0.001)
            DR.start_stream(writer)
            world = GN.create_world(spec)
            GN.add_logger!(world, logger)
            result = GN.run(world)
            @test DR.finish_stream!(writer) >= 0
            @test writer.cursor == result.ticks_executed
            messages = decode_stream(stream)
            @test messages[1]["type"] == "started"
            @test count(message -> message["type"] == "started", messages) == 1
            @test findfirst(message -> message["type"] == "rows", messages) > 1
        end
    end
end
