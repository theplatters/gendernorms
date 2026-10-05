module GenderNorms

import Ark
import Dates
import Graphs
import Random
import TOML
import UUIDs
using Distributions: Normal

include("components.jl")

include("resources/utility_functions.jl")
include("resources/social_network.jl")
include("resources/observers.jl")
include("resources/properties.jl")
include("resources/shock.jl")

include("optim/core.jl")
include("optim/labour_optimization.jl")
include("optim/transfer_optimization.jl")

include("systems/household_bargaining.jl")
include("systems/initialisation.jl")
include("systems/statistics.jl")
include("systems/shocks.jl")
include("systems/preferences.jl")
include("systems/norm_perception.jl")

include("runtime/model_interface.jl")
include("runtime/run_spec.jl")
include("runtime/run_result.jl")
include("runtime/logging.jl")
include("runtime/run_context.jl")
include("runtime/runner.jl")
include("runtime/gender_norms_model.jl")

for_gender(x, ::Male)::Float64 = x.men
for_gender(x, ::Female)::Float64 = x.woman

gender_mean(x) = (x.men + x.woman) / 2

end
