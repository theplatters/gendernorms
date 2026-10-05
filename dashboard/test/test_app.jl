# Headless HTTP smoke tests of the dashboard app.
#
# Starts the Genie app on a free loopback port with a temp record root,
# checks `/healthz`, the page, and the stylesheet route, runs one tiny
# end-to-end run through the manager (streamed metrics equal a direct
# `GenderNorms.run`, the promoted record loads equal), and shuts down
# cleanly with no leaked presentation tasks.

"""
    free_port()::Int

Return a free TCP port on the loopback interface. Binds a listener to
port 0, reads back the assigned port, and closes the listener. Returns
the port number.
"""
function free_port()::Int
    socket = Sockets.listen(Sockets.IPv4(127, 0, 0, 1), 0)
    port = Sockets.getsockname(socket)[2]
    close(socket)
    return Int(port)
end

"""
    http_get(url::String)

Issue one HTTP GET request through the Genie stack's HTTP client. Takes
the URL and returns the response with its numeric `status` and body
`text`.
"""
function http_get(url::String)
    response = Genie.Renderer.HTTP.get(url)
    return (; status = response.status, text = String(response.body))
end

@testset "app" begin
    root = mktempdir()
    manager = DR.RunManager(; runs_root = root, worker_threads = 2)
    port = free_port()
    UI.start_app!(manager; host = "127.0.0.1", port = port)
    try
        @testset "healthz reports status" begin
            response = http_get("http://127.0.0.1:$port/healthz")
            @test response.status == 200
            payload = JSON.parse(response.text)
            @test payload["name"] == "gendernorms-dashboard"
            @test payload["version"] == UI.DASHBOARD_VERSION
            @test payload["queue_depth"] == 0
            @test payload["jobs"] == 0
        end

        @testset "page renders the dashboard components" begin
            response = http_get("http://127.0.0.1:$port/")
            @test response.status == 200
            html = response.text
            @test count("<plotly", html) == 1
            @test occursin("active_plot", html)
            @test occursin("/dashboard.css", html)
            @test occursin("job_rows", html)
            @test occursin("run_rows", html)

            config = findfirst("gn-config", html)
            plots = findfirst("gn-plot-area", html)
            log = findfirst("gn-run-log", html)
            @test config !== nothing
            @test plots !== nothing
            @test log !== nothing
            @test config.start < plots.start < log.start

            @test occursin("gn-add-plot", html)
            @test occursin("toggle_line", html)
            @test occursin("event.line = line.key", html)
            @test occursin("event.plot_id = line.plot_id", html)
            @test occursin("event.checked = event.target.checked", html)
            @test occursin("activate_plot", html)
            @test occursin("remove_plot", html)
            @test occursin("add_plot", html)
            @test occursin("line_groups", html)
            @test occursin("plot_tabs", html)
        end

        @testset "stylesheet is served" begin
            response = http_get("http://127.0.0.1:$port/dashboard.css")
            @test response.status == 200
            @test occursin("gn-plot-canvas", response.text)
        end

        @testset "a tiny run completes and records match a direct run" begin
            spec = tiny_spec(name = "app-e2e", seed = 5, ticks = 5, agents_per_gender = 30)
            job_id = DR.enqueue!(manager, spec)
            summary = wait_for_job(manager, job_id; timeout = 300.0)
            @test summary.state === DR.JOB_COMPLETED
            @test summary.progress == 1.0

            reference = GN.run(GN.create_world(spec))
            @test GN.is_success(reference)

            snapshot = DR.path_snapshot(manager, summary.run_id)
            @test snapshot.ticks == reference.ticks
            @test snapshot.metrics == reference.metrics

            loaded = DR.load_record!(manager, summary.run_id)
            @test loaded.state === DR.JOB_COMPLETED
            @test loaded.ticks == reference.ticks
            @test loaded.metrics == reference.metrics
        end
    finally
        UI.stop_app!()
        DR.shutdown!(manager)
    end

    @testset "shutdown detaches every presentation task" begin
        @test isempty(UI.SESSIONS)
    end
end
