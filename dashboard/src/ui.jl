# Single-page Stipple UI of the dashboard.
#
# `ui` renders the page in three regions: the configuration form
# (StippleUI controls) in the narrow left column beside the wider plot
# area (plot tab strip with one visible chart and its per-plot line
# tickboxes) in the top row, and the full-width run log (job table and
# run list with their row actions and notes) below. Exactly one plot is
# visible at a time; the "+" button creates further plots. Row and tab
# actions carry their run, job, plot, or line key through the `@on`
# event preprocessor, so every action reaches the handlers of
# `reactive_model.jl` by id only.

"""
    form_section(title, parts...)

One titled section of the configuration form. Takes the heading and the
section elements and returns the section container div.
"""
function form_section(title::AbstractString, parts...)
    return htmldiv(vcat(Any[h4(String(title))], collect(Any, parts)); class = "gn-section")
end

"""
    metric_checkboxes()

Metric selection checkboxes of the Basic section: one checkbox per
`KNOWN_METRICS` entry (all eight model metrics) bound to the `metrics`
array field. Returns the checkbox elements.
"""
function metric_checkboxes()
    return [checkbox(metric, :metrics; val = metric, dense = true) for metric in KNOWN_METRICS]
end

"""
    config_form()

Configuration form of the page (the narrow left column of the top
row): the Basic, Network, Utility, Advanced, and Dashboard sections
with their `DashboardModel` fields, followed by the submit and cancel
buttons. Network and utility parameter inputs are shown only for the
applicable type (matching the active keys of
`DashboardRuntime.NETWORK_PARAMS` and `UTILITY_PARAMS`). Returns the
form elements.
"""
function config_form()
    return htmldiv(
        [
            h2("Configuration"),
            form_section(
                "Basic",
                textfield("Name", :name),
                textfield("Seed", :seed),
                textfield("Ticks", :ticks),
                textfield("Agents per gender", :agents_per_gender),
                p("Metrics"; class = "gn-label"),
                metric_checkboxes()...,
            ),
            form_section(
                "Network",
                select(
                    :network_type;
                    label = "Network type",
                    options = NETWORK_TYPE_OPTIONS,
                    dense = true,
                ),
                htmldiv(
                    [textfield("p", :network_p)];
                    class = "gn-field",
                    @if("network_type == 'random'"),
                ),
                htmldiv(
                    [
                        textfield("Neighbors per side", :network_neighbors_per_side),
                        textfield("Rewiring", :network_rewiring),
                    ];
                    class = "gn-field",
                    @if("network_type == 'watts_strogatz'"),
                ),
                htmldiv(
                    [textfield("m", :network_m)];
                    class = "gn-field",
                    @if(
                        "network_type == 'preferential_attachment' || network_type == 'homophily' || network_type == 'similarity'"
                    ),
                ),
                htmldiv(
                    [textfield("Trait", :network_trait)];
                    class = "gn-field",
                    @if("network_type == 'similarity'"),
                ),
            ),
            form_section(
                "Utility",
                select(
                    :utility_type;
                    label = "Utility type",
                    options = UTILITY_TYPE_OPTIONS,
                    dense = true,
                ),
                textfield("Weight self", :utility_w_self),
                textfield("Weight partner", :utility_w_partner),
                textfield("Weight transfer", :utility_w_transfer),
                htmldiv(
                    [textfield("Beta (CES only)", :utility_beta)];
                    class = "gn-field",
                    @if("utility_type == 'ces'"),
                ),
            ),
            form_section(
                "Advanced",
                textfield("Standard deviation", :std_dev),
                textfield("Initial transfer", :initial_transfer),
                textfield("Initial lambda", :initial_lambda),
                textfield("Paid time (men)", :paid_time_men),
                textfield("Paid time (women)", :paid_time_women),
                textfield("Mean wage (men)", :mean_wage_men),
                textfield("Mean wage (women)", :mean_wage_women),
                textfield("Mean preference (men)", :mean_preference_men),
                textfield("Mean preference (women)", :mean_preference_women),
                textfield("Initial conformism (men)", :initial_conformism_men),
                textfield("Initial conformism (women)", :initial_conformism_women),
            ),
            form_section(
                "Dashboard",
                checkbox("Record each run to the record root", :record_run; dense = true),
                p("Recorded runs are staged and promoted atomically after clean completion."; class = "gn-hint"),
            ),
            htmldiv(
                [
                    btn("Submit", @on(:click, :submit), color = "primary"),
                    btn("Cancel active run", @on(:click, :cancel_active)),
                    btn("Refresh records", @on(:click, :refresh_records)),
                ];
                class = "gn-actions",
            ),
        ];
        class = "gn-form gn-config",
    )
end

"""
    plot_tab_strip()

Plot switcher above the chart: one tab button per plot (labelled
`"Plot <id>"`, the active tab highlighted) with a close button on every
deletable plot, followed by the "+" button that creates further plots.
Tabs render from the reactive `plot_tabs` view; only one plot is
visible at a time. Returns the tab strip element.
"""
function plot_tab_strip()
    tab = button(
        "{{ tab.label }}";
        @on(:click, :activate_plot, "event.plot_id = tab.id"),
        Symbol(":class") => "tab.active ? 'gn-tab gn-tab-active' : 'gn-tab'",
    )
    close = button(
        "x";
        class = "gn-tab-close",
        @on(:click, :remove_plot, "event.plot_id = tab.id"),
        @showif("tab.can_close"),
    )
    return htmldiv(
        [
            htmldiv(
                [tab, close];
                class = "gn-tab-item",
                @for("tab in plot_tabs"),
                Symbol(":key") => "tab.id",
            ),
            button(
                "+";
                class = "gn-btn gn-add-plot",
                title = "add plot",
                @on(:click, :add_plot),
            ),
        ];
        class = "gn-plot-tabs",
    )
end

"""
    line_checkbox()

One line tickbox of the active plot: a checkbox bound to the line's
checked flag and its metric title. Clicking the box reaches
`handle_toggle_line!` with the line key, the plot id the row was
rendered for, and the desired checked state, so even a delayed event
sets that line in its originating plot only. Returns the checkbox row.
"""
function line_checkbox()
    return htmldiv(
        [
            input(;
                type = "checkbox",
                class = "gn-line-box",
                Symbol(":checked") => "line.checked",
                @on(
                    :click,
                    :toggle_line,
                    "event.line = line.key; event.plot_id = line.plot_id; event.checked = event.target.checked"
                ),
            ),
            span("{{ line.label }}"; class = "gn-line-label"),
        ];
        class = "gn-line",
    )
end

"""
    line_selector()

Line tickboxes of the active plot: one run-labelled group per plotted
run (from the reactive `line_groups` view) with one tickbox per metric
the run carries. The tickboxes are the plot's line selection; runs are
added and removed in the run log below. Returns the selector element.
"""
function line_selector()
    items = htmldiv(
        [line_checkbox()];
        class = "gn-line-items",
        @for("line in group.lines"),
    )
    groups = htmldiv(
        [p("{{ group.label }}"; class = "gn-line-run"), items];
        class = "gn-line-group",
        @for("group in line_groups"),
    )
    return htmldiv(
        [
            p("Lines"; class = "gn-label"),
            groups,
            p(
                "Select a run in the run log below to add its lines here.";
                class = "gn-hint",
                @showif("line_groups.length == 0"),
            ),
        ];
        class = "gn-lines",
    )
end

"""
    plot_area()

The plot area of the page (the wide right column of the top row): the
heading with the "Jump to latest" control, the plot tab strip with the
"+" button, the single visible chart, the y-axis note, the per-plot
line tickboxes, and the display notes. Returns the block element.
"""
function plot_area()
    return htmldiv(
        [
            htmldiv(
                [
                    h2("Metric paths"),
                    btn("Jump to latest", @on(:click, :jump_latest)),
                    p(
                        "Display reduced to the point budget of the plot.";
                        class = "gn-hint",
                        @showif("display_reduced"),
                    ),
                ];
                class = "gn-block-head",
            ),
            plot_tab_strip(),
            htmldiv([plotly(:active_plot)]; class = "gn-plot-canvas"),
            p(@text("axis_label"); class = "gn-hint gn-axis"),
            line_selector(),
            htmldiv(
                [p("{{ warning }}", @for("warning in data_warnings"))];
                class = "gn-warnings",
                @showif("data_warnings.length > 0"),
            ),
        ];
        class = "gn-block gn-plot-area",
    )
end

"""
    job_table()

Live job table: one row per submitted job with name, state, queue
position, progress, and the cancel and clone actions. Rows render from
the reactive `job_rows` view. Returns the table element.
"""
function job_table()
    rows = tr(
        [
            td("{{ job.name }}"),
            td("{{ job.state }}"),
            td("{{ job.queue_label }}"),
            td("{{ job.progress_label }}"),
            td(
                [
                    button(
                        "Cancel";
                        class = "gn-btn",
                        @on(:click, :cancel_job, "event.job_id = job.key"),
                        @showif("job.can_cancel"),
                    ),
                    button(
                        "Clone";
                        class = "gn-btn",
                        @on(:click, :clone_config, "event.key = job.key"),
                        @showif("job.can_clone"),
                    ),
                ],
            ),
        ];
        @for("job in job_rows"),
        Symbol(":key") => "job.key",
    )
    return htmldiv(
        [
            h2("Jobs"),
            table(
                [
                    thead(tr([th("Run"), th("State"), th("Queue"), th("Progress"), th("Actions")])),
                    tbody([rows]),
                ];
                class = "gn-table",
            ),
        ];
        class = "gn-block",
    )
end

"""
    run_table()

Run log list of live and recorded runs: one row per run with its label,
source, seed, presentation status, and the plot, load, replay, and
clone actions. Rows render from the reactive `run_rows` view; *Plot*
adds the run's lines to the active plot, *Unplot* removes the run and
its lines from every plot. Returns the table element.
"""
function run_table()
    rows = tr(
        [
            td("{{ run.label }}"),
            td("{{ run.source }}"),
            td("{{ run.seed }}"),
            td("{{ run.state }}"),
            td(
                [
                    button(
                        "{{ run.select_label }}";
                        class = "gn-btn",
                        @on(:click, :select_run, "event.key = run.key"),
                    ),
                    button(
                        "Load";
                        class = "gn-btn",
                        @on(:click, :load_record, "event.key = run.key"),
                        @showif("run.can_load"),
                    ),
                    button(
                        "Replay";
                        class = "gn-btn",
                        @on(:click, :replay_run, "event.key = run.key"),
                        @showif("run.can_replay"),
                    ),
                    button(
                        "Clone";
                        class = "gn-btn",
                        @on(:click, :clone_config, "event.key = run.key"),
                        @showif("run.can_clone"),
                    ),
                ],
            ),
            td("{{ run.notes }}"),
        ];
        @for("run in run_rows"),
        Symbol(":key") => "run.key",
    )
    return htmldiv(
        [
            h2("Runs"),
            table(
                [
                    thead(tr([th("Run"), th("Source"), th("Seed"), th("State"), th("Actions"), th("Notes")])),
                    tbody([rows]),
                ];
                class = "gn-table",
            ),
        ];
        class = "gn-block",
    )
end

"""
    run_log()

The full-width run log below the top row: the job table and the run
list with their row actions and notes. Returns the container element.
"""
function run_log()
    return htmldiv([job_table(), run_table()]; class = "gn-run-log")
end

"""
    ui()

Render the dashboard page. Takes no arguments and returns the page
HTML: header and status line, validation problem display, the
configuration form beside the plot area, and the run log below both.
"""
function ui()
    return join(
        [
            htmldiv(
                [
                    h1("GenderNorms dashboard"),
                    span(@text("status_line"); class = "gn-status"),
                ];
                class = "gn-head",
            ),
            htmldiv(
                [ul([li("{{ problem }}")]; @for("problem in problems"))];
                class = "gn-problems",
                @showif("problems.length > 0"),
            ),
            htmldiv([config_form(), plot_area()]; class = "gn-columns"),
            run_log(),
        ],
    )
end
