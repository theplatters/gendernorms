module GenderNorms

import Ark
import Graphs

include("components.jl")
include("components.jl")
include("systems/household_bargaining.jl")
include("resources/social_network.jl")
include("resources/observers.jl")
include("resources/properties.jl")
include("resources/utility_functions.jl")

include("systems/initialisation.jl")

for_gender(x, ::Male)::Float64 = x.men
for_gender(x, ::Female)::Float64 = x.woman

gender_mean(x) = (x.men + x.woman) / 2

end
