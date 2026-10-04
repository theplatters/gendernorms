# Single-page Stipple UI of the dashboard.
#
# `ui` renders the page: the configuration form (StippleUI controls) in
# sections, the live job table and run selection list with their row
# actions, the three StipplePlotly panels with the "Jump to latest"
# control, the validation problem display, and the status line. Row
# actions carry their run or job key through the `@on` event
# preprocessor, so every action reaches the handlers of
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
`PANEL_METRICS` entry bound to the `metrics` array field. Returns the
checkbox elements.
"""
function metric_checkboxes()
    return [checkbox(metric, :metrics; val = metric, dense = true) for metric in PANEL_METRICS]
end

"""
    config_form()

Configuration form of the page: the Basic, Network, Utility, Advanced,
and Dashboard sections with their `DashboardModel` fields, followed by
the submit and cancel buttons. Network and utility parameter inputs are
shown only for the applicable type (matching the active keys of
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
        class = "gn-form",
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

Run selection list of live and recorded runs: one row per run with its
label, source, seed, presentation status, and the plot, visibility,
load, replay, and clone actions. Rows render from the reactive
`run_rows` view. Returns the table element.
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
                        "{{ run.visibility_label }}";
                        class = "gn-btn",
                        @on(:click, :toggle_visibility, "event.key = run.key"),
                        @showif("run.selected"),
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
    panel_block(field::Symbol, metric::AbstractString)

One chart panel. Takes the reactive plot field and its metric name and
returns the panel with the heading and the StipplePlotly component.
"""
function panel_block(field::Symbol, metric::AbstractString)
    return htmldiv(
        [h4(PANEL_TITLES[metric]), plotly(field)];
        class = "gn-panel",
    )
end

"""
    panels_block()

The three chart panels of the page (men, women, and gap) with the
"Jump to latest" control and the display notes. Returns the panel grid.
"""
function panels_block()
    return htmldiv(
        [
            htmldiv(
                [
                    h2("Metric paths"),
                    btn("Jump to latest", @on(:click, :jump_latest)),
                    p(
                        "Display reduced to the point budget of each panel.";
                        class = "gn-hint",
                        @showif("display_reduced"),
                    ),
                ];
                class = "gn-block-head",
            ),
            htmldiv(
                [
                    panel_block(:men_plot, PANEL_METRICS[1]),
                    panel_block(:women_plot, PANEL_METRICS[2]),
                    panel_block(:gap_plot, PANEL_METRICS[3]),
                ];
                class = "gn-panels",
            ),
            htmldiv(
                [p("{{ warning }}", @for("warning in data_warnings"))];
                class = "gn-warnings",
                @showif("data_warnings.length > 0"),
            ),
        ];
        class = "gn-block",
    )
end

"""
    ui()

Render the dashboard page. Takes no arguments and returns the page
HTML: header and status line, validation problem display, the
configuration form beside the job and run tables, and the three plot
panels.
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
            htmldiv([config_form(), htmldiv([job_table(), run_table()]; class = "gn-side")]; class = "gn-columns"),
            panels_block(),
        ],
    )
end
