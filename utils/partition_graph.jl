using EGA
using CSV
using DataFrames


N = 125 # number of partitions: 125/90/60

nodes = DataFrame!(CSV.File("nodes.csv"; limit=1186)) # sans loads: 1186/917/585
links = DataFrame!(CSV.File("links.csv"; limit=1185)) # sans xfmrs

A = adjacency_matrix(nodes.name, [links.from links.to])
W =     edge_weights(nodes.name, [links.from links.to], [links.R1 links.X1]; Ybase=0.0172)

#******************************#
pid = partition_graph(A, W, N) #
#******************************#

sn = [] # super-nodes
ph = [] # phases

for n=1:N
	i = pid .== n

	DM = sum(A[i,i]; dims=2) |> vec          # degree matrix
	np = map(x -> length(x), nodes.phase[i]) # number of phases

	df = sort(DataFrame(nd=nodes.name[i], ph=nodes.phase[i], np=np, DM=DM), [:np,:DM]; rev=true)
	push!(sn, df.nd[1])
	push!(ph, df.ph[1])
end

CSV.write("np.csv", DataFrame(no=nodes.name, pid=pid))
CSV.write("ps.csv", DataFrame(pid=1:N, sn=sn, ph=ph))
