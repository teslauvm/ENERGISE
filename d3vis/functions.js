function gr_plot(file_nodes, file_links, plot_id, plot_geom) {
	if (typeof file_nodes === "undefined") { file_nodes = "dat/nodes.csv"; }
	if (typeof file_links === "undefined") { file_links = "dat/links.csv"; }
	if (typeof plot_id    === "undefined") { plot_id = "#gr_plot"; }
	if (typeof plot_geom  === "undefined") {
		plot_geom = {};
		plot_geom.outer_height = 700; //px
		plot_geom.outer_width  = 700; //px
		plot_geom.margin  = {top:10, right:10, bottom:50, left:10}; //px
		plot_geom.padding = {top:10, right:10, bottom:10, left:10}; //px
		plot_geom.height = plot_geom.outer_height - (plot_geom.margin["top"]+plot_geom.margin["bottom"]+plot_geom.padding["top"]+plot_geom.padding["bottom"]);
		plot_geom.width  = plot_geom.outer_width  - (plot_geom.margin["left"]+plot_geom.margin["right"]+plot_geom.padding["left"]+plot_geom.padding["right"]);
	}

	Promise.all([
		d3.csv(file_nodes, d => {
			return {id: parseInt(d.id),
				x:  parseFloat(d.x),
				y:  parseFloat(d.y)};
		}),
		d3.csv(file_links, d => {
			return {id:   parseInt(d.id),
				from: parseInt(d.from),
				to:   parseInt(d.to)};
		})
	]).then(
		([nodes, links]) => {
			just_graph(nodes, links, plot_id, plot_geom);
		}
	);
}


function pf_plot(vmag, flow, file_nodes, file_links, plot_id, plot_geom) {
	if (typeof vmag       === "undefined") { alert("vmag is undefined!"); return false; }
	if (typeof flow       === "undefined") { alert("flow is undefined!"); return false; }
	if (typeof file_nodes === "undefined") { file_nodes = "dat/nodes.csv"; }
	if (typeof file_links === "undefined") { file_links = "dat/links.csv"; }
	if (typeof plot_id    === "undefined") { plot_id = "#pf_plot"; }
	if (typeof plot_geom  === "undefined") {
		plot_geom = {};
		plot_geom.outer_height = 700; //px
		plot_geom.outer_width  = 700; //px
		plot_geom.margin  = {top:10, right:10, bottom:50, left:10}; //px
		plot_geom.padding = {top:10, right:10, bottom:10, left:10}; //px
		plot_geom.height = plot_geom.outer_height - (plot_geom.margin["top"]+plot_geom.margin["bottom"]+plot_geom.padding["top"]+plot_geom.padding["bottom"]);
		plot_geom.width  = plot_geom.outer_width  - (plot_geom.margin["left"]+plot_geom.margin["right"]+plot_geom.padding["left"]+plot_geom.padding["right"]);
	}

	Promise.all([
		d3.csv(file_nodes, d => {
			return {id: parseInt(d.id),
				x:  parseFloat(d.x),
				y:  parseFloat(d.y)};
		}),
		d3.csv(file_links, d => {
			return {id:   parseInt(d.id),
				from: parseInt(d.from),
				to:   parseInt(d.to)};
		})
	]).then(
		([nodes, links]) => {
			for (let i = 0; i < nodes.length; i++) { nodes[i]["vmag"] = vmag[i]; }
			for (let i = 0; i < links.length; i++) { links[i]["flow"] = flow[i]; }
			flow_graph(nodes, links, plot_id, plot_geom);
		}
	);
}


function ts_plot(vmag, flow, file_tser, file_nodes, file_links, show_points, plot_id, plot_geom) {
	if (typeof vmag        === "undefined") { alert("vmag is undefined!"); return false; }
	if (typeof flow        === "undefined") { alert("flow is undefined!"); return false; }
	if (typeof file_tser   === "undefined") { file_tser = "dat/tser.csv"; }
	if (typeof file_nodes  === "undefined") { file_nodes = "dat/nodes.csv"; }
	if (typeof file_links  === "undefined") { file_links = "dat/links.csv"; }
	if (typeof show_points === "undefined") { show_points = false; }
	if (typeof plot_id     === "undefined") { plot_id = "#ts_plot"; }
	if (typeof plot_geom   === "undefined") {
		plot_geom = {};
		plot_geom.height = 350; //px
		plot_geom.width  = 700; //px
		plot_geom.margin = {top:50, right:10, bottom:10, left:10};
	}

	Promise.resolve(
		d3.csv(file_tser, d => {
			var parseUtc = d3.utcParse("%Y-%m-%d %H:%M:%S");
			return {time: parseUtc(d.timestamp_utc),
				load: parseFloat(d.load_MW)};
		})
	).then(
		tser => {
			tsline_graph(vmag, flow, tser, file_nodes, file_links, show_points, plot_id, plot_geom);
		}
	);
}


function just_graph(nodes, links, plot_id, plot_geom) {
	d3.select(plot_id).selectAll("*").remove();

	// https://bl.ocks.org/mbostock/3019563:
	var plot = d3.select(plot_id)
		.attr("height", plot_geom.outer_height)
		.attr("width",  plot_geom.outer_width)
		.attr("transform", `translate(${plot_geom.margin.left},${plot_geom.margin.top})`);

	var _plot_ = plot.append("g")
		.attr("transform", `translate(${plot_geom.padding.left},${plot_geom.padding.top})`);

	var x = d3.scaleLinear()
		.domain(d3.extent(nodes, d => d.x))
		.range([0, plot_geom.width]);

	var y = d3.scaleLinear()
		.domain(d3.extent(nodes, d => d.y))
		.range([plot_geom.height, 0]);

	var _x_ = {};
	var _y_ = {};
	for (let node of nodes) {
		_x_[node["id"]]  = x(node["x"]);
		_y_[node["id"]]  = y(node["y"]);
	}

	var callout = d3.tip()
		.attr("class", "tooltip")
		.html(array => {var tip= "<div style='padding-bottom:3px'>" + "</div>";
			for (let a of array) { tip += "<div>" + a + "</div>"; }
			return tip; });
	_plot_.call(callout);

	_plot_.selectAll(".node")
		.data(nodes)
		.enter()
		.append("circle")
		.attr("class", "node")
		.attr("cx", d => _x_[d["id"]])
		.attr("cy", d => _y_[d["id"]])
		.attr("r",  2)
		.attr("fill", "#000000")
		.on("mouseover", d => callout.show([d["id"]]))
		.on("mouseout",  d => callout.hide());

	_plot_.selectAll(".link")
		.data(links)
		.enter()
		.append("line")
		.attr("class", "link")
		.attr("x1", d => _x_[d["from"]])
		.attr("y1", d => _y_[d["from"]])
		.attr("x2", d => _x_[d["to"]])
		.attr("y2", d => _y_[d["to"]])
		.style("stroke-width", 2)
		.style("stroke", "#cccccc");
}


function flow_graph(nodes, links, plot_id, plot_geom, max_flow) {
	d3.select(plot_id).selectAll("*").remove();

	// https://bl.ocks.org/mbostock/3019563:
	var plot = d3.select(plot_id)
		.attr("height", plot_geom.outer_height)
		.attr("width",  plot_geom.outer_width)
		.attr("transform", `translate(${plot_geom.margin.left},${plot_geom.margin.top})`);

	var _plot_ = plot.append("g")
		.attr("transform", `translate(${plot_geom.padding.left},${plot_geom.padding.top})`);

	var x = d3.scaleLinear()
		.domain(d3.extent(nodes, d => d.x))
		.range([0, plot_geom.width]);

	var y = d3.scaleLinear()
		.domain(d3.extent(nodes, d => d.y))
		.range([plot_geom.height, 0]);

	if (typeof max_flow === "undefined") { max_flow = 450; } //Amperes

	var stroke_width = d3.scaleQuantize()
		.domain([0, max_flow])
		.range([2, 4, 6, 8, 10, 12, 14, 16, 18, 20]);

	var color_scheme = ["#008000","#006600", "#daa520","#ae8419", "#ff0000","#cc0000"];
	var stroke_color = d3.scaleThreshold()
		.domain([0.05, 0.25, 0.50, 0.75, 1.00])
		.range(color_scheme);

	var node_link      = {};
	var _stroke_width_ = {};
	var _stroke_color_ = {};
	for (let link of links) {
		if (typeof node_link[link["from"]] === "undefined") { node_link[link["from"]] = [] }
		if (typeof node_link[link["to"]]   === "undefined") { node_link[link["to"]]   = [] }
		node_link[link["from"]].push(link["id"]);
		node_link[link["to"]].push(link["id"]);

		if (typeof link["rating"] === "undefined") { link["rating"] = max_flow; }

		_stroke_width_[link["id"]] = stroke_width(link["flow"]);
		_stroke_color_[link["id"]] = stroke_color(link["flow"]/link["rating"]);
	}

	var radius = {};
	var fill   = {};
	Object.keys(node_link).forEach(k => {
		var stroke_width__node_link  = [];
		var darkest_color__node_link = [];

		Object.values(node_link[k]).forEach(v => {
			stroke_width__node_link.push(_stroke_width_[v]);
			darkest_color__node_link.push(color_scheme.indexOf(_stroke_color_[v])); });

		radius[k] = d3.max(stroke_width__node_link)/2;
		fill[k]   = color_scheme[d3.max(darkest_color__node_link)];
	});

	var name = {};
	var _x_  = {};
	var _y_  = {};
	for (let node of nodes) {
		name[node["id"]] = node["id"];
		_x_[node["id"]]  = x(node["x"]);
		_y_[node["id"]]  = y(node["y"]);
	}

	var callout = d3.tip()
		.attr("class", "tooltip")
		.html(array => {var tip= "<div style='padding-bottom:3px'>" + "</div>";
			for (let a of array) { tip += "<div>" + a + "</div>"; }
			return tip; });
	_plot_.call(callout);

	_plot_.selectAll(".node")
		.data(nodes)
		.enter()
		.append("circle")
		.attr("class", "node")
		.attr("cx", d => _x_[d["id"]])
		.attr("cy", d => _y_[d["id"]])
		.attr("r",  d => radius[d["id"]])
		.attr("fill", d => fill[d["id"]])
		.on("mouseover", d => callout.show([d["id"], sprintf("%.2f pu", d["vmag"])]))
		.on("mouseout",  d => callout.hide());

	_plot_.selectAll(".link")
		.data(links)
		.enter()
		.append("line")
		.attr("class", "link")
		.attr("x1", d => _x_[d["from"]])
		.attr("y1", d => _y_[d["from"]])
		.attr("x2", d => _x_[d["to"]])
		.attr("y2", d => _y_[d["to"]])
		.style("stroke-width", d => _stroke_width_[d["id"]])
		.style("stroke",       d => _stroke_color_[d["id"]])
		.on("mouseover", d => callout.show([sprintf("%s => %s",name[d["from"]],name[d["to"]]), sprintf("%.2f Amperes (rated %.0f Amperes)",d["flow"],d["rating"])]))
		.on("mouseout",  d => callout.hide());

	// d3-legend.susielu.com:
	var legend = plot.append("g")
		.attr("class", "legendQuant")
		.attr("transform", `translate(${0.65*plot_geom.width},${0.80*plot_geom.height})`);
	legend.call(d3.legendColor()
		.scale(stroke_color)
		.title("Proximity to Line Limit:")
		.labels(["0%", "5%", "25%", "50%", "75%", "100%"])
		.labelAlign("start")
		.shapeWidth(35) //px
		.orient("horizontal"));
}


// Based principally on https://observablehq.com/@d3/line-chart-with-tooltip:
function tsline_graph(vmag, flow, tser, file_nodes, file_links, show_points, plot_id, plot_geom) {
	d3.select(plot_id).selectAll("*").remove();

	if (typeof file_nodes === "undefined") { file_nodes = "dat/nodes.csv"; }
	if (typeof file_links === "undefined") { file_links = "dat/links.csv"; }

	var plot = d3.select(plot_id)
		.attr("height", plot_geom.height)
		.attr("width",  plot_geom.width)
		.style("overflow", "visible")
		.append("g");

	var x = d3.scaleTime()
		.domain(d3.extent(tser, d => d.time))
		.nice()
		.range([plot_geom.margin.left, plot_geom.width-plot_geom.margin.right]);

	var y = d3.scaleLinear()
		.domain(d3.extent(tser, d => d.load))
		.nice()
		.range([plot_geom.height-plot_geom.margin.bottom, plot_geom.margin.top]);

	var xaxis = g => g
		.attr("transform", `translate(0,${plot_geom.height-plot_geom.margin.bottom})`)
		.call(d3.axisBottom(x).ticks(plot_geom.width/80).tickSizeOuter(0))
		.call(g => g.select(".domain").remove())
		.style("font-size", "16px");

	var yaxis = g => g
		.attr("transform", `translate(${plot_geom.margin.left},0)`)
		.call(d3.axisLeft(y))
		.call(g => g.select(".domain").remove())
		.style("font-size", "16px");

	plot.append("g").call(xaxis);
	plot.append("g").call(yaxis);

	var line = d3.line()
		.curve(d3.curveStep)
		.x(d => x(d.time))
		.y(d => y(d.load));

	plot.append("path")
		.datum(tser)
		.attr("d", line)
		.attr("stroke", "steelblue")
		.attr("stroke-width", 2)
		.attr("fill", "none");

	if (show_points) {
		plot.selectAll(".point")
			.data(tser)
			.enter()
			.append("circle")
			.attr("class", "point")
			.attr("cx", d => x(d.time))
			.attr("cy", d => y(d.load))
			.attr("r", 4)
			.attr("fill", "mediumblue");
	}

	const _x_ = [];
	for (let i = 0; i < tser.length; i++) { _x_.push(x(tser[i].time)); }

	plot.on("click", function() { var i = d3.bisectLeft(_x_, d3.mouse(this)[0]);
		return pf_plot(vmag[i], flow[i], file_nodes, file_links);
	});

	var tooltip = plot.append("g");
	plot.on("mousemove", function() { var i = d3.bisectLeft(_x_, d3.mouse(this)[0]);
		var t = tser[i].time;
		var v = tser[i].load;
		tooltip.attr("transform", `translate(${x(t)},${y(v)})`)
			.call(callout,
				`${t.toLocaleString(undefined, {dateStyle:"short", timeStyle:"short"})}**
				Load: ${v} MW
				**click to view the corresponding power flow`);
	});
	plot.on("mouseleave", () => tooltip.call(callout, null));

	plot.append("text")
		.text("Load (MW):")
		.attr("x", plot_geom.width/2)
		.attr("y", plot_geom.margin.top/2)
		.style("text-anchor", "middle")
		.style("font-size", "20px");

	var callout = (g, value) => {
		if (!value) return g.style("display", "none");
		g.style("display",null).style("pointer-events","none");
		const path = g.selectAll("path").data([null]).join("path").attr("fill","#fffafa").attr("stroke","black");
		const text = g.selectAll("text").data([null]).join("text").call(text => text.selectAll("tspan").data((value+"").split(/\n/)).join("tspan").attr("x",0).attr("y", (d,i) => `${i*1.1}em`).text(d => d));
		const {x, y, width:w, height:h} = text.node().getBBox();
		text.attr("transform", `translate(${-w/2},${15-y})`);
		path.attr("d", `M${-w/2-10},5H-5l5,-5l5,5H${w/2+10}v${h+20}h-${w+20}z`);
	}
}
