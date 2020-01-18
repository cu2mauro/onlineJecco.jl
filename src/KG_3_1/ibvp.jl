
using DifferentialEquations
# using Vivi

function unpack_dom(ucoord)
    Nsys = length(ucoord)
    Nus  = [ucoord[i].nodes for i in 1:Nsys]

    Nu_lims = zeros(typeof(Nsys), Nsys + 1)
    for i in 1:Nsys
        Nu_lims[i+1] = Nu_lims[i] + Nus[i]
    end

    function (f)
        [f[Nu_lims[i]+1:Nu_lims[i+1],:,:] for i in 1:Nsys]
    end
end

# FIXME
# function write_out(out, fieldnames, coordss)
#     Nsys   = length(fieldnames)
#     ucoord = [coordss[i][1] for i in 1:Nsys]
#     unpack = unpack_dom(ucoord)

#     function (u)
#         phis = unpack(u)
#         Vivi.output(out, fieldnames, phis, coordss)
#         nothing
#     end
# end

function ibvp(par_grid::ParamGrid, par_id::ParamID,
              par_evol::ParamEvol, par_io::ParamIO)

    systems = Jecco.KG_3_1.create_sys(par_grid)
    Nsys    = length(systems)

    ucoords = [systems[i].ucoord for i in 1:Nsys]
    unpack  = unpack_dom(ucoords)

    phi0s = initial_data(systems, par_id)
    ID    = vcat(phi0s...)

    rhs! = Jecco.KG_3_1.setup_rhs(phi0s, systems, unpack)

    dt0   = par_evol.dt
    tspan = (0.0, par_evol.tmax)

    if par_evol.ODE_method == "RK4"
        alg = RK4()
    elseif par_evol.ODE_method == "AB3"
        alg = AB3()
    else
        error("Unknown ODE_method")
    end

    prob  = ODEProblem(rhs!, ID, tspan, systems)
    # http://docs.juliadiffeq.org/latest/basics/integrator.html
    integrator = init(prob, alg, save_everystep=false, dt=dt0, adaptive=false)

    # tinfo  = Vivi.TimeInfo()

    # write initial data
    # FIXME
    # Jecco.out_info(tinfo.it, tinfo.t, ID, "phi", 1, 200)
    Jecco.out_info(0, 0.0, ID, "phi", 1, 200)

    fieldnames = ["phi c=$i" for i in 1:Nsys]
    fields     = phi0s

    # FIXME
    # coordss    = [systems[i].coords for i in 1:Nsys]

    # out    = Vivi.Output(par_io.folder, par_io.prefix, par_io.out_every, tinfo)
    # output = write_out(out, fieldnames, coordss)
    # output(ID)

    for (u,t) in tuples(integrator)
        # tinfo.it += 1
        # tinfo.dt  = integrator.dt
        # tinfo.t   = t

        # FIXME
        @show t
        # Jecco.out_info(tinfo.it, tinfo.t, u, "phi", 1, 200)
        # output(u)
    end

    nothing
end
