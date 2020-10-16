using EGA
using FileIO
using CSV
using DataFrames
using SparseArrays
using Printf


#=
The GridLab-D model prepared by this code works for the following ORU distribution feeders (located in Allendale, NJ):
39-1-13 (bank 139);
39-2-13 (bank 239);
39-4-13 (bank 239).

Capacitors and Regulators are not accounted for herein and are manually incorporated later.
=#


# INPUT PARAMETERS --
ED      = ENV["HOME"]*"/data/ORU/DRIVE" # EPRI DRIVE directory
CID     = "_UID_39-1-13_FDR"            # circuit id
iSWITCH = 0                             # the switch number (int >=1) to open/close using "eventgen"; 0: all switches closed
DT      = 60                            # time interval (seconds) for recorders
TZ      = "EST+5EDT"                    # time zone
TS      = "2016-08-01 00:00:00"         # time stamp (i.e., start and stop time)

# INPUT DATA-FRAMES --
df_b = DataFrame!(CSV.File("$ED/$(CID)_buses.csv";    copycols=true))
df_s = DataFrame!(CSV.File("$ED/$(CID)_sections.csv"; copycols=true))
df_d = DataFrame!(CSV.File("$ED/$(CID)_data.csv";     copycols=true))
df_x = DataFrame!(CSV.File("$ED/$(CID)_xfmrs.csv";    copycols=true))

# transformer connect_type (ORU/ConEd => GridLab-D):
Xc = Dict("Single Phase"           => "SINGLE_PHASE",
          "Single Phase Pad Mount" => "SINGLE_PHASE",
          "Open Wye"               => "WYE_WYE",
          "Wye Bank"               => "WYE_WYE",
          "Three Phase Pad Mount"  => "WYE_WYE")

# transformer R and X (p.u. Ohm):
Xz = Dict("Single Phase"           => Dict("R" => 0.015, "X" => 0.060), # X:R = 4:1
          "Single Phase Pad Mount" => Dict("R" => 0.015, "X" => 0.060),
          "Open Wye"               => Dict("R" => 0.020, "X" => 0.100), # X:R = 5:1
          "Wye Bank"               => Dict("R" => 0.025, "X" => 0.150), # X:R = 6:1
          "Three Phase Pad Mount"  => Dict("R" => 0.025, "X" => 0.150))

epsz = 1e-6 # Ohms
epsZ = [
epsz*(1.00+1.00*im)   epsz*(0.33+0.33*im)   epsz*(0.33+0.33*im);
epsz*(0.33+0.33*im)   epsz*(1.00+1.00*im)   epsz*(0.33+0.33*im);
epsz*(0.33+0.33*im)   epsz*(0.33+0.33*im)   epsz*(1.00+1.00*im)
]

NVL = 240.0 # nominal voltage for loads

recorders = Dict("node"          => ["voltage"],
                 "overhead_line" => ["current_out"],
                 "load"          => ["voltage"])

cxps = ["MAG"] # complex parts -- "MAG": magnitude & "ANG_DEG": angle_degrees

# object numbering scheme:
const il  = 10000 # load:                      10001-20000
const iol = 20000 # overhead_line:             20001-30000
const ilc = 30000 # line_configuration:        30001-40000
const isw = 40000 # switch:                    40001-50000
const ieg = 50000 # eventgen:                  50001-60000
const it  = 60000 # transformer:               60001-70000
const itc = 70000 # transformer_configuration: 70001-80000

const root3 = sqrt(3)

# unit conversion:
UC = Dict("micro"      => 1.000E-06,
          "milli"      => 1.000E-03,
          "centi"      => 1.000E-01,
          "kilo"       => 1.000E+03,
          "Mega"       => 1.000E+06,
          "Giga"       => 1.000E+09,
          "feet_miles" => 1.894E-04)

ai  = Dict('A'=>1, 'B'=>2, 'C'=>3)
ia  = Dict(1=>"A", 2=>"B", 3=>"C")
abc = "ABC"


switchON = iSWITCH >= 1 ? true : false

numbus = nrow(df_b)
numsec = nrow(df_s)

opsec = findall(df_s.Open_Closed .== "Open")
numops = length(opsec)

fb = copy(df_s.FromBus)
tb = copy(df_s.ToBus)

ni = Dict() # NodeID=>i
for i=1:numbus
	push!(ni, df_b.NodeID[i] => i)
end

if switchON
	for i=1:numops
		push!(ni, "switch_$i" => numbus+i)
		df_s.ToBus[opsec[i]] = "switch_$i"
	end
	numBus = numbus+numops
	numSec = numsec+numops
else
	numBus = numbus
	numSec = numsec
end

RANK = zeros(Int64,numBus) # =0: island; =1: source-node or dead-end; >1: multiply-connected
for i=1:numsec
	RANK[ni[fb[i]]] += 1
	RANK[ni[tb[i]]] += 1
end

if switchON
	for i=1:numops
		RANK[numbus+i] = 2 # doubly-connected by definition
	end
else
	for i=1:numops
		RANK[ni[fb[opsec[i]]]] -= 1
		RANK[ni[tb[opsec[i]]]] -= 1
	end
end


glm = open("model.glm", "w")
nod = open("nodes.csv", "w")
lin = open("links.csv", "w")
lno = open("lnode.csv", "w")
zlt = open("zlt.csv",   "w") # Z lookup table (for Nawaf)

@printf(glm, "clock { timezone  %s; starttime '%s'; stoptime '%s'; }\n\n", TZ, TS, TS)
@printf(glm, "#set relax_naming_rules=1;\n")
@printf(glm, "#set iteration_limit=9;\n\n")
@printf(glm, "module powerflow { solver_method NR; }\n")
@printf(glm, "module tape;\n")
@printf(glm, "module reliability;\n\n")

@printf(nod, "name,x,y,phase,loaded\n")
@printf(lin, "name,from,to,phase,R1,X1,R0,X0,status,mvline\n")
@printf(lno, "load,node,phase,kW,kVA\n")
@printf(zlt, "from,to,phases,Z\n")


R1 = zeros(Float64,numbus)
X1 = zeros(Float64,numbus)
R0 = zeros(Float64,numbus)
X0 = zeros(Float64,numbus)

nodes = [] # excluding (fabricated) switch nodes

for i=1:numbus
	if RANK[i] > 0
		@printf(glm, "object node:%d {\n", i)
		@printf(glm, "\tname            node_%d; // NodeID: %s\n", i, df_b.NodeID[i])
		@printf(glm, "\tphases          %s;\n", df_b.Phases[i])
		@printf(glm, "\tnominal_voltage %.1f;\n", df_b.baseV[i]/root3)
		if df_b.NodeID[i] == df_d.Source_Node[1]
			@printf(glm, "\tbustype         SWING;\n")
		end
		@printf(glm, "}\n\n")

		@printf(nod, "%d,%.1f,%.1f,%s,%d\n", i, df_b.xCoord[i], df_b.yCoord[i], df_b.Phases[i], 0)

		az = (df_d.FeederHeadV[1]/df_b.baseV[i])^2 # (to) adjust Z

		R1[i] = df_b.R1[i]/az
		X1[i] = df_b.X1[i]/az
		R0[i] = df_b.R0[i]/az
		X0[i] = df_b.X0[i]/az

		push!(nodes, i)
	end
end

ln = length(nodes)
ei = sparse(nodes, repeat([1],inner=ln), 1:ln, maximum(nodes), 1) # external=>internal nodes map

if switchON
	for i=1:numops
		k = ni[tb[opsec[i]]]

		@printf(glm, "object node:%d {\n", numbus+i)
		@printf(glm, "\tname            node_fabricated_%d;\n", i)
		@printf(glm, "\tphases          %s;\n", df_b.Phases[k])
		@printf(glm, "\tnominal_voltage %.1f;\n", df_b.baseV[k]/root3)
		@printf(glm, "}\n\n")

		@printf(nod, "%d,%.1f,%.1f,%s,%d\n", numbus+i, df_b.xCoord[k], df_b.yCoord[k], df_b.Phases[k], 0)
	end
end


Y  = zeros(ComplexF64,3ln,3ln) # 3-phase Ybus
A  = zeros(Float64,ln,ln)      # adjacency matrix
dz = zeros(ComplexF64,3,3)

for i=1:numsec
	if RANK[ni[df_s.FromBus[i]]] > 0 && RANK[ni[df_s.ToBus[i]]] > 0
		f = ni[fb[i]]
		t = ni[tb[i]]

		@printf(glm, "object overhead_line:%d {\n", iol+i)
		@printf(glm, "\tname          overhead_line_%d;\n", i)
		@printf(glm, "\tfrom          node:%d;\n", ni[df_s.FromBus[i]])
		@printf(glm, "\tto            node:%d;\n", ni[df_s.ToBus[i]])
		@printf(glm, "\tphases        %s;\n",      df_s.Phasing[i])
		@printf(glm, "\tconfiguration line_configuration:%d;\n", ilc+i)
		@printf(glm, "\tlength        1.0;\n")
		@printf(glm, "}\n\n")

		if length(df_s.Phasing[i]) == 3
			dR1 = R1[t]-R1[f]
			dX1 = X1[t]-X1[f]
			dR0 = R0[t]-R0[f]
			dX0 = X0[t]-X0[f]

			# solve: Z00 = ZS+2ZM; Z11 = Z22 = ZS-ZM
			# (eqs 4.73 & 4.74, w.h. kersting, distribution system modeling & analysis, 3rd ed.)
			dRS = (dR0+2dR1)/3
			dXS = (dX0+2dX1)/3
			dRM = (dR0-dR1)/3
			dXM = (dX0-dX1)/3
		else
			dRS = dR1 = R1[t]-R1[f]
			dXS = dX1 = X1[t]-X1[f]
			dRM = dR0 = 0.0
			dXM = dX0 = 0.0
		end

		# zero out spurious values of dRS, dRM, dXS, and dXM:
		(dRS < 0) && (dRS = 0)
		(dRM < 0) && (dRM = 0)
		(dXS < 0) && (dXS = 0)
		(dXM < 0) && (dXM = 0)

		ixs = [ai[phase] for phase in df_s.Phasing[i]]

		dz[:,:] = [dRS+dXS*im   dRM+dXM*im   dRM+dXM*im;
		dRM+dXM*im   dRS+dXS*im   dRM+dXM*im;
		dRM+dXM*im   dRM+dXM*im   dRS+dXS*im]

		try
			global idz = inv(dz[ixs,ixs])
			global len = sqrt((df_b.xCoord[f]-df_b.xCoord[t])^2 + (df_b.yCoord[f]-df_b.yCoord[t])^2) # feet
		catch
			dz[:,:]    = epsZ
			global idz = inv(dz[ixs,ixs])
			global len = 1.0
		end

		@printf(glm, "object line_configuration:%d {\n", ilc+i)
		@printf(glm, "\tname line_configuration_%d;\n", i)
		for p1 in df_s.Phasing[i]
			for p2 in df_s.Phasing[i]
				@printf(glm, "\tz%d%d  %.3e%+.3ej;\n", ai[p1], ai[p2], real(dz[ai[p1],ai[p2]])/UC["feet_miles"], imag(dz[ai[p1],ai[p2]])/UC["feet_miles"])
			end
		end
		@printf(glm, "}\n\n")

		@printf(lin, "%d,%d,%d,%s,%.3e,%.3e,%.3e,%.3e,%d,%d\n", i, ni[df_s.FromBus[i]], ni[df_s.ToBus[i]], df_s.Phasing[i], dR1/len, dX1/len, dR0/len, dX0/len, 1,1)

		fi = ixs .+ 3*(ei[f]-1)
		ti = ixs .+ 3*(ei[t]-1)

		Y[fi,ti] = -idz
		Y[ti,fi] = Y[fi,ti]

		A[ei[f],ei[t]] = 1
		A[ei[t],ei[f]] = 1

		@printf(zlt, "%d,%d,%s,\"%s\"\n", ni[df_s.FromBus[i]], ni[df_s.ToBus[i]], df_s.Phasing[i], join(dz[ixs,ixs],";"))
	end
end

for n=1:ln
	n3 = 3*(n-1)
	for i = findall(A[n,:] .== 1)
		i3 = 3*(i-1)
		Y[n3+1:n3+3,n3+1:n3+3] += -Y[n3+1:n3+3,i3+1:i3+3]
	end
end

save("Y.jld2",
     "Y",  sparse(Y),
     "A",  sparse(A),
     "ei", ei,
     "ni", ni)


if switchON
	for i=1:numops
		@printf(glm, "object switch:%d {\n", isw+i)
		@printf(glm, "\tname   switch_%d;\n", i)
		@printf(glm, "\tfrom   node:%d;\n", numbus+i)
		@printf(glm, "\tto     node:%d;\n", ni[tb[opsec[i]]])
		@printf(glm, "\tphases %s;\n", df_s.Phasing[opsec[i]])
		@printf(glm, "\tstatus CLOSED;\n")
		@printf(glm, "}\n\n")

		@printf(lin, "%d,%d,%d,%s,%s,%s,%s,%s,%d,%d\n", numsec+i, numbus+i, ni[tb[opsec[i]]], df_s.Phasing[opsec[i]], 0.0, 0.0, 0.0, 0.0, 1, 1)
	end

	@printf(glm, "object eventgen:%d {\n", ieg+iSWITCH)
	@printf(glm, "\tname           eventgen_%d;\n", iSWITCH)
	@printf(glm, "\tfault_type     \"SW-ABC\";\n")
	@printf(glm, "\tmanual_outages \"switch_%d, %s, %s\";\n", iSWITCH, TS, TS)
	@printf(glm, "}\n\n")

	@printf(glm, "object fault_check {\n")
	@printf(glm, "\tname            fault_handler;\n")
	@printf(glm, "\tcheck_mode      ONCHANGE;\n")
	@printf(glm, "\tstrictly_radial false;\n")
	@printf(glm, "\teventgen_object eventgen_%d;\n", iSWITCH)
	@printf(glm, "}\n\n")
end


df_x.connected_components = string.(df_x.connected_components)

iX  = find_in(df_x.connected_components, df_b.NodeID)
Xcc = df_x.connected_components[iX]                     # NodeIDs with transformers

nl = Dict() # number of loads per NodeID
for cc in unique(Xcc)
	push!(nl, cc => count(cc .== Xcc))
end

l = 0 # load index

for i=iX
	cc = df_x.connected_components[i]

	if RANK[ni[cc]] > 0
		global l += 1

		Vpr = df_x.V_pri[i]*UC["kilo"] # transfomer   primary_voltage
		Vse = NVL*root3                #            secondary_voltage

		# transformer phases and power_rating (kVA):
		if df_x.type[i] == "Single Phase" || df_x.type[i] == "Single Phase Pad Mount"
			phases = ia[df_x.phase_a[i]]
			rating = df_x.kVA_a[i]
			Vpr /= root3
			Vse /= root3
		elseif df_x.type[i] == "Open Wye"
			phases = @sprintf("%s%s", ia[df_x.phase_a[i]], ia[df_x.phase_b[i]])
			rating = df_x.kVA_a[i] + df_x.kVA_b[i]
		elseif df_x.type[i] == "Wye Bank"
			phases = abc
			rating = df_x.kVA_a[i] + df_x.kVA_b[i] + df_x.kVA_c[i]
		elseif df_x.type[i] == "Three Phase Pad Mount"
			phases = abc
			rating = df_x.kVA_a[i]
		else
			@printf("%s_xfo.csv: index=%d: %s?\n", CID, i, df_x.type[i])
			error("unsupported transformer type")
		end

		np = length(phases) # number of phases

		@printf(glm, "object load:%d {\n", il+l)
		@printf(glm, "\tname            load_%d; // #customers=%d\n", l, df_x.num_customers[i])
		@printf(glm, "\tphases          %s;\n", phases)
		@printf(glm, "\tnominal_voltage ")
		@printf(glm, "%.1f;\n", NVL)

		for p in phases
			file = "players/d_$(l)_$(p)_$(ni[cc]).csv"

			@printf(glm, "\tobject player {\n")
			@printf(glm, "\t\tfile     %s;\n", file)
			@printf(glm, "\t\tproperty constant_power_%s;\n", p)
			@printf(glm, "\t};\n")
		end
		@printf(glm, "}\n\n")

		@printf(nod, "%d,%.1f,%.1f,%s,%d\n", il+l, df_b.xCoord[ni[cc]], df_b.yCoord[ni[cc]], phases, 1)

		@printf(lno, "%d,%d,%s,%.1f,%.1f\n", l, ni[cc], phases, df_b.kWABC_load[ni[cc]]/nl[cc], rating)

		@printf(glm, "object transformer:%d {\n", it+l)
		@printf(glm, "\tname          transformer_%d;\n", l)
		@printf(glm, "\tfrom          node:%d;\n", ni[cc])
		@printf(glm, "\tto            load:%d;\n", il+l)
		@printf(glm, "\tphases        %s;\n", phases)
		@printf(glm, "\tconfiguration transformer_configuration:%d;\n", itc+l)
		@printf(glm, "}\n\n")

		@printf(lin, "%d,%d,%d,%s,%.3e,%.3e,%.3e,%.3e,%d,%d\n", numSec+l, ni[cc], il+l, phases, 0.0,0.0,0.0,0.0, 1,0)

		@printf(glm, "object transformer_configuration:%d {\n", itc+l)
		@printf(glm, "\tname              transformer_configuration_%d;\n", l)
		@printf(glm, "\tconnect_type      %s;\n",   Xc[df_x.type[i]])
		@printf(glm, "\tpower_rating      %d;\n",   rating)
		@printf(glm, "\tprimary_voltage   %.1f;\n", Vpr)
		@printf(glm, "\tsecondary_voltage %.1f;\n", Vse)
		@printf(glm, "\tresistance        %.3f;\n", Xz[df_x.type[i]]["R"])
		@printf(glm, "\treactance         %.3f;\n", Xz[df_x.type[i]]["X"])
		@printf(glm, "}\n\n")

	end
end


for (object, attributes) in recorders
	for attribute in attributes
		for phase in abc
			for cxp in cxps
				@printf(glm, "object group_recorder{\n")
				@printf(glm, "file         ./%s_%s_%s_%s.csv;\n", object,    attribute, phase, cxp)
				@printf(glm, "group        \"class=%s\";\n",      object)
				@printf(glm, "property     %s_%s;\n",             attribute, phase)
				@printf(glm, "complex_part %s;\n",                cxp)
				@printf(glm, "interval     %d;\n",                DT)
				@printf(glm, "}\n\n")
			end
		end
	end
end


close(glm)
close(nod)
close(lin)
close(lno)
close(zlt)
