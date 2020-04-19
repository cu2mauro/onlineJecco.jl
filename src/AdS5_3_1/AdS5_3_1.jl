module AdS5_3_1

using Jecco
using Parameters

abstract type GridType end
abstract type Inner <: GridType end
abstract type Outer <: GridType end

export ParamBase, ParamGrid, ParamID, ParamEvol, ParamIO
export Potential
export VV # this will contain the potential
export Inner, Outer, AbstractSystem, System
export BulkVars, BoundaryVars, GaugeVars


# Note: in the future we may promote this to something like BulkVars{Ng,T}, to
# dispatch on Ng (the type of equations to be solved on each grid)

# TODO: remove d*dt fields from this struct ?

struct BulkVars{T}
    B1     :: T
    B2     :: T
    G      :: T
    phi    :: T
    S      :: T
    Fx     :: T
    Fy     :: T
    B1d    :: T
    B2d    :: T
    Gd     :: T
    phid   :: T
    Sd     :: T
    A      :: T
    dB1dt  :: T
    dB2dt  :: T
    dGdt   :: T
    dphidt :: T
end

BulkVars(B1, B2, G, phi, S, Fx, Fy, B1d, B2d, Gd, phid, Sd, A, dB1dt, dB2dt,
         dGdt, dphidt) = BulkVars{typeof(B1)}(B1, B2, G, phi, S, Fx, Fy, B1d, B2d,
                                              Gd, phid, Sd, A, dB1dt, dB2dt, dGdt, dphidt)

function BulkVars(Nxx::Vararg)
    B1     = zeros(Nxx...)
    B2     = copy(B1)
    G      = copy(B1)
    phi    = copy(B1)
    S      = copy(B1)
    Fx     = copy(B1)
    Fy     = copy(B1)
    B1d    = copy(B1)
    B2d    = copy(B1)
    Gd     = copy(B1)
    phid   = copy(B1)
    Sd     = copy(B1)
    A      = copy(B1)
    dB1dt  = copy(B1)
    dB2dt  = copy(B1)
    dGdt   = copy(B1)
    dphidt = copy(B1)

    BulkVars{typeof(B1)}(B1, B2, G, phi, S, Fx, Fy, B1d, B2d, Gd, phid, Sd, A,
                         dB1dt, dB2dt,dGdt, dphidt)
end

function BulkVars(B1::Array{T,N}, B2::Array{T,N}, G::Array{T,N},
                  phi::Array{T,N}) where {T<:Number,N}
    S      = similar(B1)
    Fx     = similar(B1)
    Fy     = similar(B1)
    B1d    = similar(B1)
    B2d    = similar(B1)
    Gd     = similar(B1)
    phid   = similar(B1)
    Sd     = similar(B1)
    A      = similar(B1)
    dB1dt  = similar(B1)
    dB2dt  = similar(B1)
    dGdt   = similar(B1)
    dphidt = similar(B1)

    BulkVars{typeof(B1)}(B1, B2, G, phi, S, Fx, Fy, B1d, B2d, Gd, phid, Sd, A,
                         dB1dt, dB2dt,dGdt, dphidt)
end


struct GaugeVars{A,T}
    xi    :: A
    kappa :: T
end

function GaugeVars(xi::Array{T,N}, kappa::T) where {T<:Number,N}
    GaugeVars{typeof(xi), typeof(kappa)}(xi, kappa)
end


function setup(par_base)
    global VV = Potential(par_base)
end


struct BoundaryVars{T}
    a4   :: T
    fx2  :: T
    fy2  :: T
end


#= Notation

for any function f we're using the following notation (let _x denote partial
derivative with respect to x)

fp  = f_r = -u^2 f_u
fd  = \dot f
ft  = \tilde f = f_x - (Fx + xi_x) f_r
fh  = \hat f   = f_y - (Fy + xi_y) f_r

=#


mutable struct AllVars{GT<:GridType,T<:Real}
    u        :: T

    phi0     :: T

    xi       :: T
    xi_x     :: T
    xi_y     :: T
    xi_xx    :: T
    xi_xy    :: T
    xi_yy    :: T

    B1       :: T
    B1p      :: T
    B1t      :: T
    B1h      :: T
    B1b      :: T
    B1s      :: T
    B1pt     :: T
    B1ph     :: T

    B2       :: T
    B2p      :: T
    B2t      :: T
    B2h      :: T
    B2b      :: T
    B2s      :: T
    B2pt     :: T
    B2ph     :: T

    G        :: T
    Gp       :: T
    Gt       :: T
    Gh       :: T
    Gb       :: T
    Gs       :: T
    Gpt      :: T
    Gph      :: T

    phi      :: T
    phip     :: T
    phit     :: T
    phih     :: T
    phib     :: T
    phis     :: T
    phipt    :: T
    phiph    :: T

    S        :: T
    Sp       :: T
    St       :: T
    Sh       :: T
    Sb       :: T
    Ss       :: T
    Spt      :: T
    Sph      :: T

    Fx       :: T
    Fxp      :: T
    Fxt      :: T
    Fxh      :: T
    Fxb      :: T
    Fxs      :: T
    Fxpt     :: T
    Fxph     :: T

    Fy       :: T
    Fyp      :: T
    Fyt      :: T
    Fyh      :: T
    Fyb      :: T
    Fys      :: T
    Fypt     :: T
    Fyph     :: T

    Sd       :: T
    B1d      :: T
    B2d      :: T
    Gd       :: T
    phid     :: T

    B2c      :: T
    Gc       :: T
    Sc       :: T
    phic     :: T
end
function AllVars{GT,T}() where {GT<:GridType,T<:AbstractFloat}
    N = 2 + 6 + 8*7 + 5 + 4
    array = zeros(N)
    AllVars{GT,T}(array...)
end


#= Notation

for any function f we're using the following convention: _x denotes partial
derivative with respect to x and

fp  = f_r  = -u^2 f_u
fpp = f_rr = 2u^3 f_u + u^4 f_uu

=#

mutable struct FxyVars{GT<:GridType,T<:Real}
    u        :: T

    xi_x     :: T
    xi_y     :: T

    B1       :: T
    B1p      :: T
    B1_x     :: T
    B1_y     :: T
    B1pp     :: T
    B1p_x    :: T
    B1p_y    :: T

    B2       :: T
    B2p      :: T
    B2_x     :: T
    B2_y     :: T
    B2pp     :: T
    B2p_x    :: T
    B2p_y    :: T

    G        :: T
    Gp       :: T
    Gpp      :: T
    G_x      :: T
    G_y      :: T
    Gp_x     :: T
    Gp_y     :: T

    phi      :: T
    phip     :: T
    phi_x    :: T
    phi_y    :: T

    S        :: T
    Sp       :: T
    S_x      :: T
    S_y      :: T
    Spp      :: T
    Sp_x     :: T
    Sp_y     :: T
end
function FxyVars{GT,T}() where {GT<:GridType,T<:AbstractFloat}
    N = 1 + 2 + 4*7 + 4
    array = zeros(N)
    FxyVars{GT,T}(array...)
end


include("param.jl")
include("system.jl")
# include("initial_data.jl")
include("potential.jl")
# include("dphidt.jl")
include("equation_inner_coeff.jl")
include("equation_outer_coeff.jl")
include("solve_nested.jl")
# include("rhs.jl")
# include("run.jl")
# include("ibvp.jl")

end
