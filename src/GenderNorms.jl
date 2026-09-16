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

for_gender(x, ::Male) = x.men
for_gender(x, ::Female) = x.woman

end
