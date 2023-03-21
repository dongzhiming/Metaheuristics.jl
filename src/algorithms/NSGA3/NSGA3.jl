mutable struct NSGA3 <: AbstractParameters
    N::Int
    η_cr::Float64
    p_cr::Float64
    η_m::Float64
    p_m::Float64
    partitions::Int
    reference_points::Array{Vector{Float64},1}
end


"""
    NSGA3(;
        N = 100,
        η_cr = 20,
        p_cr = 0.9,
        η_m = 20,
        p_m = 1.0 / D,
        partitions = 12,
        reference_points = Vector{Float64}[],
        information = Information(),
        options = Options(),
    )

Parameters for the metaheuristic NSGA-III.

Parameters:

- `N` Population size.
- `η_cr`  η for the crossover.
- `p_cr` Crossover probability.
- `η_m`  η for the mutation operator.
- `p_m` Mutation probability (1/D for D-dimensional problem by default).
- `reference_points` reference points usually generated by `gen_ref_dirs`.
- `partitions` number of Das and Dennis's reference points if `reference_points` is empty.

To use NSGA3, the output from the objective function should be a 3-touple
`(f::Vector, g::Vector, h::Vector)`, where `f` contains the objective functions,
`g` and `h` are inequality, equality constraints respectively.

A feasible solution is such that `g_i(x) ≤ 0 and h_j(x) = 0`.


```julia
using Metaheuristics


# Objective function, bounds, and the True Pareto front
f, bounds, pf = Metaheuristics.TestProblems.get_problem(:DTLZ2)


# define the parameters (use `NSGA3()` for using default parameters)
nsga3 = NSGA3(p_cr = 0.9)

# optimize
status = optimize(f, bounds, nsga3)

# show results
display(status)
```

"""
function NSGA3(;
    N = 100,
    η_cr = 20,
    p_cr = 0.9,
    η_m = 20,
    p_m = -1,
    partitions=12,
    reference_points=Vector{Float64}[],
    information = Information(),
    options = Options(),
)

    parameters = NSGA3(N, promote( Float64(η_cr), p_cr, η_m, p_m )..., partitions,
                      reference_points)
    Algorithm(
        parameters,
        information = information,
        options = options,
    )

end



function update_state!(
    status::State,
    parameters::NSGA3,
    problem::AbstractProblem,
    information::Information,
    options::Options,
    args...;
    kargs...
    )

    Q = reproduction(status, parameters, problem)

    append!(status.population, create_solutions(Q, problem))
    
    # non-dominated sort, elitist removing via niching
    environmental_selection!(status.population, parameters)
end


function environmental_selection!(population, parameters::NSGA3)
    truncate_population_nsga3!(population,parameters.reference_points,parameters.N)
end

function truncate_population_nsga3!(population, reference_points, N)
    fast_non_dominated_sort!(population)
    
    k = 1
    l = 1
    while l <= N
        k = population[l].rank
        l += 1
    end

    let k = k
        l = findlast(sol -> sol.rank == k, population)
        deleteat!(population, l+1:length(population))
    end

    l = findfirst(sol -> sol.rank == k, population)
    niching!(population, reference_points, N, l)
end

distance_point_to_rect(s, w) = @fastmath norm(s - (dot(w,s) / dot(w, w))*w  )

function associate!(nich, nich_freq, distance, F, reference_points, l) 
    N = length(F)

    # find closest nich to corresponding solution
    for i = 1:N
        for j = 1:length(reference_points)
            d = distance_point_to_rect(F[i], reference_points[j])

            distance[i] < d && continue

            distance[i] = d
            nich[i] = j
        end

        # not associate last  front
        if i < l
            nich_freq[nich[i]] += 1
        end
        
    end
end

function hyperplane_normalization(population) 
    M = length(fval(population[1]))

    ideal_point = ideal(population)
    nadir_point = fill(Inf, length(ideal_point))

    Fx = fvals(population) .- ideal_point'

    # identify extreme points
    extreme_points = zeros(Int, M)
    w = LinearAlgebra.I + fill(1e-6, M, M)

    for i in 1:M
        extreme_points[i] = argmin(nadir(Fx' ./ w[i,:]))
    end

    # check if intercepts can be obtained
    S = Fx[extreme_points,:]
    if LinearAlgebra.det(S) ≈ 0 # check if soluble matrix
        nadir_point = nadir(population)
    else
        hyperplane = S \ ones(M)
        intercepts = 1 ./ hyperplane # intercepts
        nadir_point = ideal_point + intercepts
    end


    ideal_point, nadir_point
end


function normalize(population) 
    ideal_point, nadir_point = hyperplane_normalization(population)

    b = nadir_point - ideal_point

    # prevent division by zero
    mask = b .< eps()
    b[mask] .= eps()

    return [ (sol.f - ideal_point) ./ b for sol in population ]
end

# get_last_front(id, population) = findall(s -> s.rank == id, population)

pick_random(itr, item) = rand(findall(i -> i == item, itr))
find_item(itr, item)  = findall(i -> i == item, itr)


function niching!(population, reference_points, N, l)
    if length(population) == N
        return
    end
    
    F = normalize(population)
    k = l

    # allocate memory
    nich = zeros(Int, length(population))
    nich_freq = zeros(Int, length(reference_points))
    available_niches = ones(Bool, length(reference_points))
    distance = fill(Inf, length(population))

    # associate to niches
    associate!(nich, nich_freq, distance, F, reference_points, l)

    # keep last front
    last_front_id = k:length(population)#get_last_front(population[end].rank, population)
    last_front = population[last_front_id]
    deleteat!(population, last_front_id)

    # last front niches information
    niches_last_front = nich[last_front_id]
    distance_last_front = distance[last_front_id]
    
    # save survivors
    i = 1
    while k <= N
        mini = minimum(view(nich_freq, available_niches))
        # nich to be assigned
        j_hat = pick_random(nich_freq, mini)

        # candidate solutions 
        I_j_hat = find_item( niches_last_front, j_hat )
        if isempty(I_j_hat)
            available_niches[j_hat] = false
            continue
        end

        if mini == 0
            ds = view(distance_last_front, I_j_hat)
            s = I_j_hat[argmin(ds)]
            push!(population, last_front[s])
        else
            s = rand(I_j_hat)
            push!(population, last_front[s])
        end

        nich_freq[j_hat] += 1
        deleteat!(last_front, s)
        deleteat!(niches_last_front, s)
        deleteat!(distance_last_front, s)

        k += 1
        
        
    end


    nothing
end



function initialize!(
    status,
    parameters::NSGA3,
    problem::AbstractProblem,
    information::Information,
    options::Options,
    args...;
    kargs...
    )

    D = getdim(problem)

    if parameters.p_m < 0.0
        parameters.p_m = 1.0 / D
    end

    if options.iterations == 0
        options.iterations = 500
    end

    if options.f_calls_limit == 0
        options.f_calls_limit = options.iterations * parameters.N + 1
    end

    status = gen_initial_state(problem, parameters, information, options,status)

    if isempty(parameters.reference_points)
        options.debug && @info "Initializing reference points..."
        # number of objectives
        m = length(status.population[1].f)

        # initialize reference points
        parameters.reference_points = gen_weights(m, parameters.partitions)
    end

    status

end

function final_stage!(
    status::State,
    parameters::NSGA3,
    problem::AbstractProblem,
    information::Information,
    options::Options,
    args...;
    kargs...
    )
    status.final_time = time()


end


###########################################
## NSGA3 reproduction
###########################################
function reproduction(status, parameters::NSGA3, problem)
    @assert !isempty(status.population)

    I = randperm(parameters.N)
    Q = zeros(parameters.N, getdim(problem))
    for i = 1:parameters.N ÷ 2

        pa = status.population[I[2i-1]]
        pb = status.population[I[2i]]

        c1, c2 = GA_reproduction(get_position(pa),
                                 get_position(pb),
                                 problem.search_space;
                                 η_cr = parameters.η_cr,
                                 p_cr = parameters.p_cr,
                                 η_m = parameters.η_m,
                                 p_m = parameters.p_m)
        Q[i,:] = c1
        Q[i+1,:] = c2       
    end

    Q
end
