using CSV
using DataFrames
using FileIO


#=
AFTERWARDS, DON'T FORGET TO DO:
sed -i 's/ + /+/g' D(S)_*.csv
=#

sbi = 126 # SWING-bus index (@reduced): 126/91/61

pre = "s" # d/s
PRE = "S" # D/S

mts = 10081 # max #timesteps

PS = DataFrame!(CSV.File("PS.csv"))
NP = DataFrame!(CSV.File("NP.csv"))
ln = DataFrame!(CSV.File("lnode.csv"))


ai = Dict('A'=>1, 'B'=>2, 'C'=>3)

N = size(PS,1)
X = zeros(ComplexF64,mts,3,N) # demand_or_solar[max_#times,3_phases,#nodes]

ini = true
for i=1:size(ln,1)
	ld = ln[i,:load]
	no = ln[i,:node]
	ph = ln[i,:phase]

	j = findall(NP.no .== no)
	k = NP.pid[j]

	for p in ph
		file = "./players/$(pre)_$(ld)_$(p)_$(no).csv"
		if isfile(file)
			df = DataFrame!(CSV.File(file; types=[String;String], header=0))
			if ini
				global ini = false
				global tis = df.Column1  #  timestamps
				global mts = length(tis) # #timestamps
			end
			X[1:mts,ai[p],k] += map(x -> parse(ComplexF64,x), df.Column2)
		end
	end
end

X = map(x -> replace(string(x), "im"=>"j"), X)

for i=setdiff(1:N, sbi)
	for p in PS.ph[i]
		CSV.write("./players/$(PRE)_$(i)_$p.csv", DataFrame(C1=tis, C2=X[1:mts,ai[p],i]); writeheader=false)
	end
end
