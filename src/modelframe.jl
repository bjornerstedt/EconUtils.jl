
"""
	modelframe(formula::EconFormula, data::AbstractDataFrame;
		contrasts::Dict = Dict())

	This formula is akin to ModelFrame for Formula, but rather than being a
	struct it returns
		data::DataFrame
		varlist::Vector{String}
		response::Vector{T}
		exogenous::Matrix{T}
		endogenous::Matrix{T}
		instruments::Matrix{T}
		absorb::Vector{Vector{Vector{Int64}}}
		clusters::Vector{Vector{Vector{Int64}}}
"""
function modelframe(formula::EconFormula,
	data::AbstractDataFrame;
	contrasts::Dict = Dict(),
	θ::Vector{T} = Vector{Real}()) where T <: Real
	response = formula.exogenous.lhs
	exogenous = StatsModels.Terms(formula.exogenous)
	endogenous = StatsModels.Terms(formula.endogenous)
	instruments = StatsModels.Terms(formula.instruments)
	absorb = StatsModels.Terms(formula.absorb)
	clusters = StatsModels.Terms(formula.clusters)
	vars = Symbol.(reduce(union, getfield.((exogenous, endogenous, instruments, absorb, clusters), :eterms)))
	df = data[vars]
	dropmissing!(df)
	mf = ModelFrame(exogenous, df, contrasts = contrasts)
	y = Vector{Float64}(model_response(mf))
	varlist = coefnames(mf)
	MM = ModelMatrix(mf)
	assign = MM.assign
	X = MM.m
	if length(endogenous.eterms) > 1
		mf = ModelFrame(endogenous, df)
		append!(varlist, coefnames(mf)[2:end])
		mm = ModelMatrix(mf)
		if unique(mm.assign) ≠ mm.assign
			@assert false "Endogenous variables must not be categorical variables with more than two levels."
		end
		append!(assign, mm.assign .+ length(unique(assign)))
		z = mm.m[:, map(elem -> elem > 0, mm.assign)]
		mf = ModelFrame(instruments, df)
		Z = ModelMatrix(mf).m[:,2:end]
	else
		z = zeros(length(y),0)
		Z = zeros(length(y),0)
	end
	D = groups(formula.absorb, data)
	R = groups(formula.clusters, data)
	if isempty(D)
		D = Vector{Vector{Vector{Int64}}}()
	elseif !isempty(θ)
		@assert length(D) == 1 "Partial demeaning is implemented for only one dimension."
		@assert length(θ) == length(D[1]) "θ must be empty or same length as D[1]."
		y = partialwithin(y, D[1], θ)
		X = partialwithin(X, D[1], θ)
		if size(z, 2) > 0
			z = partialwithin(z, D[1], θ)
			Z = partialwithin(Z, D[1], θ)
		end
	else
		(m, singletons) = dropsingletons!(D)
		remapper = makeremapper(m, singletons)
		remapping!(D, remapper)
		validobs = setdiff(1:length(y), singletons)
		y = within(y[validobs], D)
		X = within(X[validobs,:], D)
		if size(z, 2) > 0
			z = within(z[validobs,:], D)
			Z = within(Z[validobs,:], D)
		end
	end
	if isempty(R)
		R = Vector{Vector{Vector{Int64}}}()
	end
	return df, varlist, assign, y, X, z, Z, D, R
end
