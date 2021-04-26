
using Jecco.AdS5_3_1

grid = SpecCartGrid3D(
    x_min            = -0.5,
    x_max            =  0.5,
    x_nodes          =  6,
    y_min            = -0.5,
    y_max            =  0.5,
    y_nodes          =  6,
    u_outer_min      =  0.1,
    u_outer_max      =  1.005,
    u_outer_domains  =  1,
    u_outer_nodes    =  48,
    u_inner_nodes    =  12,
    fd_order         =  4,
    sigma_diss       =  0.2,
)

potential = AdS5_3_1.PhiPoli(
    alpha   = -0.55,
    beta    = 0.1,
    #gamma  = 0.0,
)

id = BlackBranePert(
    energy_dens = -0.53,
    phi0        = 1.0,
    phi2        = 1.2,
    #a4_ampx     = -0.05,
    #a4_kx       = 1,
    xi0         = 0.05,
    AH_pos      = 0.95,
    xmax        = grid.x_max,
    xmin        = grid.x_min,
    ymin        = grid.y_min,
    ymax        = grid.y_max,
)

evoleq = AffineNull(
    phi0           = id.phi0,
    potential      = potential,
    gaugecondition = ConstantAH(u_AH = id.AH_pos),
)

diag = DiagAH(
    find_AH_every_t    = 1.0,
)

io = InOut(
    out_boundary_every_t        = 0.2,
    out_bulk_every_t            = 1.0,
    out_gauge_every_t           = 0.2,
    #out_bulkconstrained_every_t = 5.0,
    #checkpoint_every_walltime_hours = 1,
    out_dir                     ="/home/mikel/Documents/Jecco.jl/data/new_potential/test",
    recover                     = :no,
    recover_dir                 = "/Users/apple/Documents/Jecco.jl/data/test/new_data/",
    #checkpoint_dir              = "/home/mikel/Documents/Jecco.jl/data/test/",
    remove_existing             = true,
)

integration = Integration(
    #dt              = 0.001,
    tmax            = 20.0,
    ODE_method      = AdS5_3_1.VCABM3(),
    #ODE_method      = AdS5_3_1.AB3(),
    adaptive        = true,
    filter_poststep = true,
)

run_model(grid, id, evoleq, diag, integration, io)

convert_to_mathematica(io.out_dir)
