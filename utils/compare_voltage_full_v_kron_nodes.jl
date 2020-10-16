using FileIO
using CSV
using DataFrames
using SparseArrays
using Printf
using Statistics


PIDs = setdiff(1:126, 107,109,110) # sans capacitor super-nodes -- 1:126, 107,109,110; 1:91, 86; 1:61, 4,48

T = 1441 # max #timesteps
V = 7621.0 # base voltage

PS = DataFrame!(CSV.File("PS.csv"))
NP = DataFrame!(CSV.File("NP.csv"))


ai = Dict('A'=>1, 'B'=>2, 'C'=>3)

N = length(PIDs)
RMSE = Array{Union{Missing,String}}(missing,N,3)   # RMSE @super-nodes:    full vs kron
MAPE = Array{Union{Missing,String}}(missing,T,N,3) # MAPE (intra-cluster): full vs kron

ix = sparsevec(PIDs, collect(1:N), maximum(PIDs))

for ph in "ABC"
	F = DataFrame!(CSV.File("./results/full/node_voltage_$(ph)_MAG.csv"; comment="#"))
	K = DataFrame!(CSV.File("./results/kron/node_voltage_$(ph)_MAG.csv"; comment="#"))

	global T = size(F,1)
	(nrow(K) != T) && error("phase $ph: F & K have unequal #rows.")

	for t=1:T
		for i in PIDs
			ni = Symbol("node_$i")
			if K[t,ni] != 0.0
				maxerr = 0.0
				for j in NP.no[NP.pid .== i]
					nj = Symbol("node_$j")
					if F[t,nj] != 0.0
						maxerr = max(maxerr, abs((K[t,ni]-F[t,nj])/F[t,nj])*100)
					end
				end
				MAPE[t,ix[i],ai[ph]] = @sprintf("%.2f", maxerr)
			end
		end
	end

	for i in PIDs
		if occursin(ph, PS.ph[i])
			f = Symbol("node_$(PS.sn[i])")
			k = Symbol("node_$i")
			RMSE[ix[i],ai[ph]] = @sprintf("%.5f", sqrt(mean((K[!,k].-F[!,f]).^2))/V)
		end
	end
end

CSV.write("mape_a.csv",  DataFrame(MAPE[1:T,:,1]); writeheader=false)
CSV.write("mape_b.csv",  DataFrame(MAPE[1:T,:,2]); writeheader=false)
CSV.write("mape_c.csv",  DataFrame(MAPE[1:T,:,3]); writeheader=false)
CSV.write("rmse_sn.csv", DataFrame(RMSE);          writeheader=false)
