using EGA
using FileIO
using CSV
using DataFrames
using LinearAlgebra
using SparseArrays
using Printf


"""
`Yr = kron_reduce_3ph(Y, subset)`

Kron-reduce a 3-phase Ybus (Y) onto a designated subset of nodes (subset).

THEORY:\n
"Kron reduction of graphs with applications to electrical networks,"\n
IEEE TCS--I: Regular Papers, Vol. 60(1), January 2013; doi:10.1109/TCSI.2012.2215780.\n
The key is to rerrange the Ybus as shown below:\n\n
Y[i,i] Y[i,e]\n
Y[e,i] Y[e,e]\n\n
i: "internal" nodes\n
e: "external" nodes\n\n
The reduced Ybus is given by:\n
`Yr = Y[i,i] - Y[i,e]*inv(Y[e,e])*Y[e,i]`
"""
function kron_reduce_3ph(Y::SparseMatrixCSC{Complex{Float64},Int64}, subset::Array{Int64,1})
	(npi, _) = findnz(diag(Y)) # node-phase index

	k = []
	for j in subset
		push!(k, 3j-2, 3j-1, 3j)
	end

	i = k[find_in(k, npi)]
	e = setdiff(npi, i)

	return Y[i,i] - Y[i,e]*inv(Matrix(Y[e,e]))*Y[e,i]
end


"""
`(ii, ij) = reconcile_indices(i, j , phi, phj)`

Reconcile the indices between two 3-phase nodes.

Input-\n
i:   beginning node-phase index of the first  node (e.g., 1)\n
j:   beginning node-phase index of the second node\n
phi: phases of the first  node (e.g., "ABC")\n
phj: phases of the second node (e.g., "ABC")

Output-\n
ii: reconciled indices for the first  node\n
ij: reconciled indices for the second node.
"""
function reconcile_indices(i::Int64, j::Int64, phi::String, phj::String)
	ii = []
	ij = []
	delta_i = 0
	delta_j = 0

	phij = intersect(phi, phj)

	if 'A' in phij
		push!(ii, i)
		push!(ij, j)
	end
	if 'A' in phi
		delta_i += 1
	end
	if 'A' in phj
		delta_j += 1
	end

	if 'B' in phij
		push!(ii, i+delta_i)
		push!(ij, j+delta_j)
	end
	if 'B' in phi
		delta_i += 1
	end
	if 'B' in phj
		delta_j += 1
	end

	if 'C' in phij
		push!(ii, i+delta_i)
		push!(ij, j+delta_j)
	end

	return Array{Int64}(ii), Array{Int64}(ij)
end


sbi = 126 # SWING-bus index (@reduced): 126/91/61

PS = DataFrame!(CSV.File("PS.csv"))
NP = DataFrame!(CSV.File("NP.csv"))

Y  = load("Y.jld2", "Y")
A  = load("Y.jld2", "A")
ei = load("Y.jld2", "ei")
ni = load("Y.jld2", "ni")

N = size(A,1)  # #nodes (@original)
n = size(PS,1) #        (@reduced)

I = Array(ei[PS.sn]) # set: "internal" nodes
E = setdiff(1:N, I)  #      "external"

# infer the reduced graph's edges (sans the node-phase mess):
D  = sum(A; dims=2) |> vec |> Diagonal          # degree    matrix (@original)
L  = sparse(D-A)                                # Laplacian matrix  ...
Lr = L[I,I] - L[I,E]*inv(Matrix(L[E,E]))*L[E,I] # ...              (@reduced)

# adjacency matrix (@reduced):
Ar = [(i != j && Lr[i,j] != 0) ? 1 : 0 for i=1:n, j=1:n]
Ar = triu(Ar)

true && CSV.write("Ar.csv", DataFrame(Ar); writeheader=false)


#**************************#
Yr = kron_reduce_3ph(Y, I) #
#**************************#


reglm = open("remod.glm", "w")
rezlt = open("rezlt.csv", "w")

@printf(reglm,
        "clock { timezone  EST+5EDT; starttime '2016-08-01 00:00:00'; stoptime '2016-08-31 23:00:00'; }
        #set relax_naming_rules=1;
        #set iteration_limit=9;
        module powerflow { solver_method NR; }
        module tape;\n\n")

@printf(rezlt, "from,to,phases,Z\n")

# unit conversion:
UC = Dict("micro"      => 1.000E-06,
          "milli"      => 1.000E-03,
          "centi"      => 1.000E-01,
          "kilo"       => 1.000E+03,
          "Mega"       => 1.000E+06,
          "Giga"       => 1.000E+09,
          "feet_miles" => 1.894E-04)

# nominal voltage (Volts):
NV = 13200/sqrt(3)

epsz = 1e-6 # Ohms
epsZ = [
epsz*(1.00+1.00*im)   epsz*(0.33+0.33*im)   epsz*(0.33+0.33*im);
epsz*(0.33+0.33*im)   epsz*(1.00+1.00*im)   epsz*(0.33+0.33*im);
epsz*(0.33+0.33*im)   epsz*(0.33+0.33*im)   epsz*(1.00+1.00*im)
] ./ UC["feet_miles"]

ai = Dict('A'=>1, 'B'=>2, 'C'=>3)


for i=1:n
	@printf(reglm, "object node:%d {\n",          i)
	@printf(reglm, "name             node_%d;\n", i)
	@printf(reglm, "phases           %s;\n",      PS.ph[i])
	@printf(reglm, "nominal_voltage  %.1f;\n",    NV)
	if i == sbi
		@printf(reglm, "bustype          SWING;\n}\n\n")
	else
		@printf(reglm, "}\n\n")

		@printf(reglm, "object load:%d {\n",         i+1000)
		@printf(reglm, "name            load_%d;\n", i)
		@printf(reglm, "phases          %s;\n",      PS.ph[i])
		@printf(reglm, "nominal_voltage %.1f;\n",    NV)
		if occursin("A", PS.ph[i])
			@printf(reglm, "object player { file load_%d_A.csv; property constant_power_A; };\n", i)
		end
		if occursin("B", PS.ph[i])
			@printf(reglm, "object player { file load_%d_B.csv; property constant_power_B; };\n", i)
		end
		if occursin("C", PS.ph[i])
			@printf(reglm, "object player { file load_%d_C.csv; property constant_power_C; };\n", i)
		end
		@printf(reglm, "}\n\n")

		@printf(reglm, "object overhead_line:%d {\n",            i+2000)
		@printf(reglm, "name          overhead_line_%d;\n",      i)
		@printf(reglm, "from          node:%d;\n",               i)
		@printf(reglm, "to            load:%d;\n",               i+1000)
		@printf(reglm, "phases        %s;\n",                    PS.ph[i])
		@printf(reglm, "configuration line_configuration:%d;\n", i+5000)
		@printf(reglm, "length        1.0;\n")
		@printf(reglm, "}\n\n")

		@printf(reglm, "object line_configuration:%d {\n", i+5000)
		@printf(reglm, "\tname line_configuration_%d;\n",  i)
		for p1 in PS.ph[i]
			for p2 in PS.ph[i]
				@printf(reglm, "\tz%d%d  %.3e%+.3ej;\n", ai[p1], ai[p2], real(epsZ[ai[p1],ai[p2]]), imag(epsZ[ai[p1],ai[p2]]))
			end
		end
		@printf(reglm, "}\n\n")
	end
end


numphs = map(x -> length(x), PS.ph)

dz = zeros(ComplexF64,3,3)
k  = 0

for i=1:n
	ii = i > 1 ? sum(numphs[1:i-1]) : 0

	for j = findall(Ar[i,:] .== 1)
		if numphs[i] > numphs[j]
			phase = PS.ph[j]
			from  = i
			to    = j
		else
			phase = PS.ph[i]
			from  = j
			to    = i
		end

		if to == sbi
			to   = from
			from = sbi
		end

		#******************NO MESHED LINKS PLEASE!****************#
		(sum(A[NP.pid .== from, NP.pid .== to]) == 0) && continue #
		#*********************************************************#

		isempty(intersect(PS.ph[i],PS.ph[j])) && error("no common phases between super-nodes $i and $j!")

		global k += 1
		@printf(reglm, "object overhead_line:%d {\n",            n-1+k+2000)
		@printf(reglm, "name          overhead_line_%d;\n",      n-1+k)
		@printf(reglm, "from          node:%d;\n",               from)
		@printf(reglm, "to            node:%d;\n",               to)
		@printf(reglm, "phases        %s;\n",                    phase)
		@printf(reglm, "configuration line_configuration:%d;\n", n-1+k+5000)
		@printf(reglm, "length        1.0;\n")
		@printf(reglm, "}\n\n")

		kx      = [ai[p] for p in phase]
		(ix,jx) = reconcile_indices(1, 1, PS.ph[i], PS.ph[j])
		ij      = j > 1 ? sum(numphs[1:j-1]) : 0

		dz[kx,kx] = -inv(Yr[ii.+ix,ij.+jx])

		@printf(reglm, "object line_configuration:%d {\n", n-1+k+5000)
		@printf(reglm, "\tname line_configuration_%d;\n",  n-1+k)
		for p1 in phase
			for p2 in phase
				@printf(reglm, "\tz%d%d  %.3e%+.3ej;\n",
				        ai[p1], ai[p2], real(dz[ai[p1],ai[p2]])/UC["feet_miles"], imag(dz[ai[p1],ai[p2]])/UC["feet_miles"])
			end
		end
		@printf(reglm, "}\n\n")

		@printf(rezlt, "%d,%d,%s,\"%s\"\n", from, to, phase, join(dz[kx,kx],";"))
	end
end


@printf(reglm,
        "object group_recorder{
        	file         ./node_voltage_A_MAG.csv;
        	group        \"class=node\";
        	property     voltage_A;
        	complex_part MAG;
        	interval     60;
        }
        object group_recorder{
        	file         ./node_voltage_B_MAG.csv;
        	group        \"class=node\";
        	property     voltage_B;
        	complex_part MAG;
        	interval     60;
        }
        object group_recorder{
        	file         ./node_voltage_C_MAG.csv;
        	group        \"class=node\";
        	property     voltage_C;
        	complex_part MAG;
        	interval     60;
        }
        object group_recorder{
        	file         ./capacitor_voltage_A_MAG.csv;
        	group        \"class=capacitor\";
        	property     voltage_A;
        	complex_part MAG;
        	interval     60;
        }
        object group_recorder{
        	file         ./capacitor_voltage_B_MAG.csv;
        	group        \"class=capacitor\";
        	property     voltage_B;
        	complex_part MAG;
        	interval     60;
        }
        object group_recorder{
        	file         ./capacitor_voltage_C_MAG.csv;
        	group        \"class=capacitor\";
        	property     voltage_C;
        	complex_part MAG;
        	interval     60;
        	}\n\n")

close(reglm)
close(rezlt)
