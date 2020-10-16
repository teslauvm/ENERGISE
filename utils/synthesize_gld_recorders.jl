using CSV
using DataFrames
using Printf


dir        = ENV["HOME"]*"/tmp/ENERGISE/39-1-13/results/full"
time_frame = collect(1:60*24)
num_xfmrs  = 465
Vbase_pri  = 7621.0
Vbase_sec  =  240.0


Va_1 = DataFrame!(CSV.File(dir*"/node_voltage_A_MAG.csv";      comment="#"))
Vb_1 = DataFrame!(CSV.File(dir*"/node_voltage_B_MAG.csv";      comment="#"))
Vc_1 = DataFrame!(CSV.File(dir*"/node_voltage_C_MAG.csv";      comment="#"))
Va_2 = DataFrame!(CSV.File(dir*"/capacitor_voltage_A_MAG.csv"; comment="#"))
Vb_2 = DataFrame!(CSV.File(dir*"/capacitor_voltage_B_MAG.csv"; comment="#"))
Vc_2 = DataFrame!(CSV.File(dir*"/capacitor_voltage_C_MAG.csv"; comment="#"))
Va_3 = DataFrame!(CSV.File(dir*"/load_voltage_A_MAG.csv";      comment="#"))
Vb_3 = DataFrame!(CSV.File(dir*"/load_voltage_B_MAG.csv";      comment="#"))
Vc_3 = DataFrame!(CSV.File(dir*"/load_voltage_C_MAG.csv";      comment="#"))

Va = [(Va_1[time_frame,2:end]./Vbase_pri |> Matrix) (Va_2[time_frame,2:end]./Vbase_pri |> Matrix) (Va_3[time_frame,2:end]./Vbase_sec |> Matrix)]
Vb = [(Vb_1[time_frame,2:end]./Vbase_pri |> Matrix) (Vb_2[time_frame,2:end]./Vbase_pri |> Matrix) (Vb_3[time_frame,2:end]./Vbase_sec |> Matrix)]
Vc = [(Vc_1[time_frame,2:end]./Vbase_pri |> Matrix) (Vc_2[time_frame,2:end]./Vbase_pri |> Matrix) (Vc_3[time_frame,2:end]./Vbase_sec |> Matrix)]

Ia = DataFrame!(CSV.File(dir*"/overhead_line_current_out_A_MAG.csv"; comment="#"))
Ib = DataFrame!(CSV.File(dir*"/overhead_line_current_out_B_MAG.csv"; comment="#"))
Ic = DataFrame!(CSV.File(dir*"/overhead_line_current_out_C_MAG.csv"; comment="#"))

num_times = length(time_frame)
Ia = [(Ia[time_frame,2:end] |> Matrix) zeros(Float64,num_times,num_xfmrs)]
Ib = [(Ib[time_frame,2:end] |> Matrix) zeros(Float64,num_times,num_xfmrs)]
Ic = [(Ic[time_frame,2:end] |> Matrix) zeros(Float64,num_times,num_xfmrs)]

CSV.write("va_unabridged.csv", DataFrame(map(x -> @sprintf("%.2f",x), Va)); writeheader=false)
CSV.write("vb_unabridged.csv", DataFrame(map(x -> @sprintf("%.2f",x), Vb)); writeheader=false)
CSV.write("vc_unabridged.csv", DataFrame(map(x -> @sprintf("%.2f",x), Vc)); writeheader=false)
CSV.write("ia_unabridged.csv", DataFrame(map(x -> @sprintf("%.2f",x), Ia)); writeheader=false)
CSV.write("ib_unabridged.csv", DataFrame(map(x -> @sprintf("%.2f",x), Ib)); writeheader=false)
CSV.write("ic_unabridged.csv", DataFrame(map(x -> @sprintf("%.2f",x), Ic)); writeheader=false)
