using EGA
using CSV
using DataFrames
using Printf


links = DataFrame!(CSV.File("zlt.csv"))
nodes = union(links.from, links.to)

nlinks = nrow(links)
status = trues(nlinks)

@printf(stdout, "from,to,broke\n")
for n in 1:nlinks
	status[n] = 0
	@printf(stdout, "%d,%d,", links.from[n], links.to[n])
	if has_islands(nodes, links[status,[:from,:to]] |> Array)
		@printf(stdout, "1\n")
	else
		@printf(stdout, "0\n")
	end
	status[n] = 1
end
