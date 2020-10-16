using CSV
using DataFrames


#=
DON'T FORGET TO DO:
sed -i 's/ + /+/g' ./players/nd_*.csv
sed -i 's/ - /-/g' ./players/nd_*.csv
=#

ln = DataFrame!(CSV.File("lnode.csv"; types=[Int64;Int64;String;Float64]))

for i=1:size(ln,1)
	ld = ln[i,:load]
	ph = ln[i,:phase]
	nd = ln[i,:node]

	for p in ph
		d = CSV.read("./players/d_$(ld)_$(p)_$(nd).csv"; header=0)
		s = CSV.read("./players/s_$(ld)_$(p)_$(nd).csv"; header=0)

		D = map(x -> parse(ComplexF64,x), d.Column2)
		S = map(x -> parse(ComplexF64,x), s.Column2)

		CSV.write("./players/nd_$(ld)_$(p)_$(nd).csv", DataFrame(C1=d.Column1, C2=map(x -> replace(string(x), "im"=>"j"), D-S)); writeheader=false)
	end
end
