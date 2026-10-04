# Smoke check of the dashboard UI stack (Genie, Stipple, StipplePlotly,
# PlotlyBase). Boots a minimal Stipple application with one reactive
# `PlotlyBase.Plot`, serves it with Genie on a free loopback port, fetches
# the page, and asserts the response contains the plot element. Run with
# `julia --project=dashboard dashboard/bin/smoke_stack.jl`; exits 0 on
# success and non-zero on failure.

using Downloads
using Genie
using PlotlyBase
using Sockets
using Stipple
using Stipple.ReactiveTools
using StipplePlotly

@app SmokeApp begin
    @in chart = Plot([PlotlyBase.scatter(x = 1:5, y = [1, 4, 9, 16, 25])])
end

function ui()
    return plotly(:chart)
end

@page("/", ui, model = SmokeApp)

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
    main()::Int

Run the UI stack smoke check. Starts the application on a free loopback
port, downloads the page, and verifies the plot element is rendered.
Returns 0 when the check passes and 1 otherwise.
"""
function main()::Int
    port = free_port()
    up(port, "127.0.0.1"; async = true, open_browser = false)
    try
        body = read(Downloads.download("http://127.0.0.1:$port/"), String)
        if !occursin("<plotly", body)
            @error "page does not contain the plot element"
            return 1
        end
        println("smoke stack ok: page served with plot element on port $port")
        return 0
    catch err
        @error "smoke stack failed" exception = (err, catch_backtrace())
        return 1
    finally
        down()
    end
end

exit(main())
