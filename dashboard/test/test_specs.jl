# Tests for the form-to-spec construction of `DashboardRuntime`
# (`dashboard/src/runtime/specs.jl`): every network and utility type
# builds a valid spec, stale hidden form keys never reach the model,
# invalid forms aggregate every problem, and the default and cloned
# forms round-trip through `GenderNorms.spec_to_dict` stably.

@testset "specs" begin
    @testset "every network type builds a valid spec" begin
        for network_type in sort!(collect(keys(DR.NETWORK_PARAMS)))
            form = tiny_form()
            form["network_type"] = network_type
            for param in DR.NETWORK_PARAMS[network_type]
                form["network_" * param] =
                    param == "trait" ? "wage" :
                    param in ("m", "neighbors_per_side") ? "2" : "0.3"
            end
            spec = DR.validate_form(form)
            @test spec isa GN.RunSpec
        end
    end

    @testset "every utility type builds a valid spec" begin
        for utility_type in sort!(collect(keys(DR.UTILITY_PARAMS)))
            form = tiny_form()
            form["utility_type"] = utility_type
            form["utility_w_self"] = "0.5"
            form["utility_w_partner"] = "0.4"
            form["utility_w_transfer"] = "0.3"
            utility_type == "ces" && (form["utility_beta"] = "0.7")
            spec = DR.validate_form(form)
            @test spec isa GN.RunSpec
        end
    end

    @testset "stale hidden keys never reach the model" begin
        form = tiny_form()
        form["network_type"] = "watts_strogatz"
        form["network_p"] = "0.9"
        form["network_m"] = "2"
        form["network_trait"] = "wage"
        form["utility_type"] = "additive"
        form["utility_beta"] = "0.9"
        dict = DR.build_spec_dict(form)
        @test Set(keys(dict["model"]["network"])) ==
            Set(["type", "neighbors_per_side", "rewiring"])
        @test Set(keys(dict["model"]["utility"])) ==
            Set(["type", "w_self", "w_partner", "w_transfer"])
        @test DR.validate_form(form) isa GN.RunSpec

        form["network_type"] = "none"
        dict = DR.build_spec_dict(form)
        @test Set(keys(dict["model"]["network"])) == Set(["type"])
        @test DR.validate_form(form) isa GN.RunSpec
    end

    @testset "invalid forms aggregate every problem" begin
        form = tiny_form()
        form["seed"] = "abc"
        form["ticks"] = "0"
        form["network_type"] = "banana"
        form["utility_w_self"] = "-1"
        problems = DR.validate_form(form)
        @test problems isa Vector{String}
        @test length(problems) >= 4
        @test any(problem -> occursin("[run.seed]", problem), problems)
        @test any(problem -> occursin("[runtime.ticks]", problem), problems)
        @test any(problem -> occursin("[model.network.type]", problem), problems)
        @test any(problem -> occursin("[model.utility.w_self]", problem), problems)
    end

    @testset "form values are parsed server-side" begin
        dict = DR.build_spec_dict(tiny_form(seed = "12", ticks = "7"))
        @test dict["run"]["seed"] === 12
        @test dict["runtime"]["ticks"] === 7
        form = tiny_form()
        form["std_dev"] = "0.35"
        @test DR.build_spec_dict(form)["model"]["std_dev"] === 0.35
    end

    @testset "blank and missing values are omitted" begin
        form = tiny_form()
        form["std_dev"] = " "
        form["name"] = ""
        delete!(form, "initial_lambda")
        dict = DR.build_spec_dict(form)
        @test !haskey(dict["model"], "std_dev")
        @test !haskey(dict["model"], "initial_lambda")
        @test !haskey(dict["run"], "name")
        @test DR.validate_form(form) isa GN.RunSpec
    end

    @testset "defaults round-trip stably" begin
        form = DR.default_form()
        dict = DR.build_spec_dict(form)
        @test dict["logging"]["outputs"] == Any[]
        first = GN.spec_to_dict(GN.parse_spec(dict))
        second = GN.spec_to_dict(GN.parse_spec(first))
        @test first == second
        rebuilt = DR.form_from_spec(GN.parse_spec(first))
        @test DR.build_spec_dict(rebuilt)["logging"]["outputs"] == Any[]
        @test DR.validate_form(rebuilt) isa GN.RunSpec
    end

    @testset "cloning replaces recorded output directories" begin
        root = mktempdir()
        spec_dict = fixture_spec_dict(
            name = "legacy",
            metrics = ["working_time_gap", "working_time_men"],
            outputs = [Dict{String,Any}("type" => "toml", "directory" => "runs")],
        )
        record_path = write_record_fixture(
            root,
            string(UUIDs.uuid4());
            name = "legacy",
            spec = spec_dict,
        )
        path = DR.read_record(record_path)
        @test path.spec !== nothing

        clone = DR.clone_form(path)
        @test clone["name"] == "legacy copy"
        @test clone["record_directory"] == DR.DEFAULT_RECORD_DIRECTORY
        @test Set(clone["metrics"]) == Set(["working_time_gap", "working_time_men"])
        dict = DR.build_spec_dict(clone)
        @test dict["logging"]["outputs"] == Any[
            Dict{String,Any}("type" => "toml", "directory" => DR.DEFAULT_RECORD_DIRECTORY),
        ]
        first = GN.spec_to_dict(GN.parse_spec(dict))
        second = GN.spec_to_dict(GN.parse_spec(first))
        @test first == second
        @test DR.validate_form(clone) isa GN.RunSpec

        custom = DR.clone_form(path; staging_dir = "tmp/staging")
        @test DR.build_spec_dict(custom)["logging"]["outputs"] ==
            Any[Dict{String,Any}("type" => "toml", "directory" => "tmp/staging")]
    end

    @testset "cloning is disabled without a valid spec" begin
        root = mktempdir()
        record_path = write_record_fixture(root, string(UUIDs.uuid4()); spec = nothing)
        path = DR.read_record(record_path)
        @test path.spec === nothing
        @test_throws ArgumentError DR.clone_form(path)
        @test_throws ArgumentError DR.clone_form(record_path)
    end
end
