abstract type AbstractGRASP <: AbstractParameters end

struct GRASP{I, T, L} <: AbstractGRASP
	initial::I
	constructor::T
	local_search::L
end

function construct(constructor)
    @error "Define your own randomized greedy constructor"
    status.stop = true
    nothing
end

include("constructor.jl")

"""
    GRASP(;initial, constructor, local_search,...)

Greedy Randomized Adaptive Search Procedure.

# Allowed parameters

- `initial`: an initial solution if necessary.
- `constructor` parameters for the greedy constructor.
- `local_search` the local search strategy `BestImprovingSearch()` (default) and `FirstImprovingSearch()`.

See [`GreedyRandomizedContructor`](@ref)

# Example: Knapsack Problem

```julia
import Metaheuristics as MH

# define type for saving knapsack problem instance
struct KPInstance
    profit
    weight
    capacity
end

function MH.compute_cost(candidates, constructor, instance::KPInstance)
    # Ration profit / weight
    ratio = instance.profit[candidates] ./ instance.weight[candidates]
    # It is assumed minimizing non-negative costs
    maximum(ratio) .- ratio
end

function main()
    # problem instance
    profit = [55, 10,47, 5, 4, 50, 8, 61, 85, 87]
    weight = [95, 4, 60, 32, 23, 72, 80, 62, 65, 46]
    capacity = 269
    optimum = 295
    instance = KPInstance(profit, weight, capacity)

    # objective function and search space
    f, search_space, _ = MH.TestProblems.knapsack(profit, weight, capacity)
    candidates = rand(search_space)

    # define each GRASP component
    constructor  = MH.GreedyRandomizedContructor(;candidates, instance, α = 0.95)
    local_search = MH.BestImprovingSearch()
    neighborhood = MH.TwoOptNeighborhood()
    grasp = MH.GRASP(;constructor, local_search)
    
    # optimize and display results
    result = MH.optimize(f, search_space, grasp)
    display(result)
    # compute GAP
    fx = -minimum(result)
    GAP = (optimum - fx) / optimum
    println("The GAP is ", GAP)
end

main()
```
"""
function GRASP(;initial=nothing, constructor=nothing, local_search=BestImprovingSearch(),
                options = Options(), information=Information())
	# TODO
	if isnothing(constructor)
        error("Provide a constructor.")
	end
    grasp = GRASP(initial, constructor, local_search)
    Algorithm(grasp; options, information)
end

iscompatible(::BitArraySpace, ::AbstractGRASP) = true
iscompatible(::PermutationSpace, ::AbstractGRASP) = true

function initialize!(status, parameters::AbstractGRASP, problem, information, options, args...; kargs...)

    if isnothing(parameters.initial)
        x0 = rand(options.rng, problem.search_space)
    else
        x0 = parameters.initial
    end
    # set default budget
    options.f_calls_limit = Inf
    if options.iterations <= 0
        options.iterations = 500
    end
    
    sol = create_solution(x0, problem)
	State(sol, [sol])
end

function update_state!(
        status,
        parameters::AbstractGRASP,
        problem,
        information,
        options,
        args...;
        kargs...
    )
    # heuristic construction
    x = construct(parameters.constructor)
    if isnothing(x) || isempty(x)
        status.stop = true
        options.debug && @error """
        Constructor is returning empty solutions. Early stopping optimization.
        """
        return
    elseif options.debug
        @info "Solution generated by `constructor`:\n$x\nPerforming local search..."
    end
    
    # perform local search and evaluate solutions
    x_improved = local_search(x, parameters.local_search, problem)

    # since local search can return a solution without evaluation
    # it is necessary to evaluate objective function
    if x_improved isa AbstractVector
        # evaluate solution
        sol = create_solution(x_improved, problem)
    elseif x_improved isa AbstractSolution
        sol = x_improved
    else
        # seems that local search returned something different to a vector
        return
    end
    options.debug && @info "Local search returned:\n$(get_position(sol))"
    
    # save best solutions
    if is_better(sol, status.best_sol)
        status.best_sol = sol
        options.debug && @info "A better solution was found."
    end
end

function final_stage!(
        status,
        parameters::AbstractGRASP,
        problem,
        information,
        options,
        args...;
        kargs...
   )
   # TODO
   nothing
end

