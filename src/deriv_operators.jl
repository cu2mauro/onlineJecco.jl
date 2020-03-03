
import Base: *
import LinearAlgebra: mul!

abstract type AbstractDerivOperator{T,N} end

D1_42_weights() = [1.0, -8.0, 0.0, 8.0, -1.0] ./ 12.0

D2_42_weights() = [-1.0, 16.0, -30.0, 16.0, -1.0] ./ 12.0


struct FiniteDiffDeriv{T<:Real,N,T2,S} <: AbstractDerivOperator{T,N}
    derivative_order        :: Int
    approximation_order     :: Int
    dx                      :: T2
    len                     :: Int
    stencil_length          :: Int
    stencil_coefs           :: S
end

struct SpectralDeriv{T<:Real,N,S} <: AbstractDerivOperator{T,N}
    derivative_order        :: Int
    len                     :: Int
    D                       :: S
end

struct CenteredDiff{N} end

function CenteredDiff{N}(derivative_order::Int,
                         approximation_order::Int, dx::T,
                         len::Int) where {T<:Real,N}
    @assert approximation_order > 1 "approximation_order must be greater than 1."

    stencil_length = derivative_order + approximation_order - 1 +
        (derivative_order+approximation_order)%2


    # TODO: this can all be improved...

    if approximation_order != 4
        error("approximation_order not implemented yet")
    end

    if derivative_order == 1
        weights = D1_42_weights()
    elseif derivative_order == 2
        weights = D2_42_weights()
    else
        error("derivative_order not implemented yet")
    end

    stencil_coefs = (1/dx^derivative_order) .* weights

    FiniteDiffDeriv{T,N,T,typeof(stencil_coefs)}(derivative_order, approximation_order,
                                                 dx, len, stencil_length, stencil_coefs)
end

CenteredDiff(args...) = CenteredDiff{1}(args...)


struct ChebDeriv{N} end

function ChebDeriv{N}(derivative_order::Int, xmin::T, xmax::T, len::Int) where {T<:Real,N}
    x, Dx, Dxx = cheb(xmin, xmax, len)

    if derivative_order == 1
        D = Dx
    elseif derivative_order == 2
        D = Dxx
    else
        error("derivative_order not implemented")
    end

    SpectralDeriv{T,N,typeof(D)}(derivative_order, len, D)
end

ChebDeriv(args...) = ChebDeriv{1}(args...)


@inline function Base.getindex(A::FiniteDiffDeriv, i::Int, j::Int)
    N      = A.len
    coeffs = A.stencil_coefs
    mid    = div(A.stencil_length, 2) + 1

    # note: without the assumption of periodicity this needs to be adapted
    idx  = 1 + mod(j - i + mid - 1, N)

    if idx < 1 || idx > A.stencil_length
        return 0.0
    else
        return coeffs[idx]
    end
end

@inline Base.getindex(A::FiniteDiffDeriv, i::Int, ::Colon) =
    [A[i,j] for j in 1:A.len]

@inline Base.getindex(A::SpectralDeriv, i, j) = A.D[i,j]


# mul! done by convolution for finite difference operators
function LinearAlgebra.mul!(df::AbstractVector, A::FiniteDiffDeriv, f::AbstractVector)
    convolve!(df, f, A)
end

# mul! done by standard matrix multiplication for Chebyshev differentiation
# matrices. This can also be done (potentially more efficiently) through
# FFT. TODO; test if worthwhile
function LinearAlgebra.mul!(df::AbstractVector, A::SpectralDeriv, f::AbstractVector)
    mul!(df, A.D, f)
end

# and now for Arrays

function LinearAlgebra.mul!(df::AbstractArray{T}, A::AbstractDerivOperator{T,N},
                            f::AbstractArray{T}) where {T,N}
    Rpre  = CartesianIndices(axes(f)[1:N-1])
    Rpost = CartesianIndices(axes(f)[N+1:end])

    _mul_loop!(df, A, f, Rpre, Rpost)
end

# this works as follows. suppose we are taking the derivative of a 4-dimensional
# array g, with coordinates w,x,y,z, and size
#
#   size(g) = (nw, nx, ny, nz)
#
# let's further suppose that we want the derivative along the x-direction (here,
# the second entry). this fixes
#
#   N = 2
#
# and then
#
#   Rpre  = CartesianIndices((nw,))
#   Rpost = CartesianIndices((ny,nz))
#
# now, the entry [Ipre,:,Ipost]
#
# slices *only* along the x-direction, for fixed Ipre and Ipost. Ipre and Ipost
# loop along Rpre and Rpost (respectively) without touching the x-direction. we
# further take care to loop in memory-order, since julia's arrays are faster in
# the first dimension.
#
# adapted from http://julialang.org/blog/2016/02/iteration
#
@noinline function _mul_loop!(df, A, f, Rpre, Rpost)
    @fastmath @inbounds for Ipost in Rpost
        @inbounds for Ipre in Rpre
            @views mul!(df[Ipre,:,Ipost], A, f[Ipre,:,Ipost])
        end
    end
    nothing
end

# convolution operation to act with derivatives on vectors. this currently
# assumes periodic BCs. adapted from
# DiffEqOperators.jl/src/derivative_operators/convolutions.jl
function convolve!(xout::AbstractVector{T}, x::AbstractVector{T},
                   A::FiniteDiffDeriv) where {T<:Real}
    N = length(x)
    coeffs = A.stencil_coefs
    mid = div(A.stencil_length, 2) + 1

    @fastmath @inbounds for i in 1:N
        sum_i = zero(T)
        @inbounds for idx in 1:A.stencil_length
            # imposing periodicity
            i_circ = 1 + mod(i - (mid-idx) - 1, N)
            sum_i += coeffs[idx] * x[i_circ]
        end
        xout[i] = sum_i
    end
    nothing
end

function *(A::AbstractDerivOperator, x::AbstractArray)
    y = similar(x)
    mul!(y, A, x)
    y
end

# make FiniteDiffDeriv a callable struct, to compute derivatives only at a given point
function (A::FiniteDiffDeriv)(x::AbstractVector{T}, i::Int) where {T<:Real}
    N = length(x)
    coeffs = A.stencil_coefs
    mid = div(A.stencil_length, 2) + 1

    sum_i = zero(T)
    @fastmath @inbounds for idx in 1:A.stencil_length
        # imposing periodicity
        i_circ = 1 + mod(i - (mid-idx) - 1, N)
        sum_i += coeffs[idx] * x[i_circ]
    end

    sum_i
end

# make SpectralDeriv a callable struct, to compute derivatives only at a given point
(A::SpectralDeriv)(x::AbstractVector{T}, i::Int) where {T<:Real} = dot(A.D[i,:], x)

# and now for Arrays
function (A::AbstractDerivOperator{T,N})(f::AbstractArray{T},
                                         idx::Vararg{Int,M}) where {T,N,M}
    Ipre  = CartesianIndex(idx[1:N-1])
    Ipost = CartesianIndex(idx[N+1:end])
    i     = idx[N]

    @views A(f[Ipre, :, Ipost], i)
end


# now for cross-derivatives. we assume that A acts on the first and B on the
# second axis of the x Matrix.

# first the FD case
function (A::FiniteDiffDeriv{T,1,T2,S})(B::FiniteDiffDeriv{T,2,T2,S}, x::AbstractMatrix{T},
                                        i::Int, j::Int) where {T<:Real,T2,S}
    NA   = A.len
    NB   = B.len
    qA   = A.stencil_coefs
    qB   = B.stencil_coefs
    midA = div(A.stencil_length, 2) + 1
    midB = div(B.stencil_length, 2) + 1

    @assert( (NA, NB) == size(x) )

    sum_ij = zero(T)
    @fastmath @inbounds for jj in 1:B.stencil_length
        # imposing periodicity
        j_circ = 1 + mod(j - (midB-jj) - 1, NB)
        sum_i  = zero(T)
        @inbounds for ii in 1:A.stencil_length
            # imposing periodicity
            i_circ = 1 + mod(i - (midA-ii) - 1, NA)

            sum_i += qA[ii] * qB[jj] * x[i_circ,j_circ]
        end
        sum_ij += sum_i
    end

    sum_ij
end

# now for spectral derivatives
function (A::SpectralDeriv{T,1,S})(B::SpectralDeriv{T,2,S}, x::AbstractMatrix{T},
                                   i::Int, j::Int) where {T<:Real,S}
    NA = A.len
    NB = B.len

    @assert( (NA, NB) == size(x) )

    sum_ij = zero(T)
    @fastmath @inbounds for jj in 1:NB
        sum_i = zero(T)
        @inbounds for ii in 1:NA
            sum_i += A[i,ii] * B[j,jj] * x[ii,jj]
        end
        sum_ij += sum_i
    end

    sum_ij
end

# we can also have mixed FD and spectral cases

function (A::SpectralDeriv{T,1,S1})(B::FiniteDiffDeriv{T,2,T2,S2}, x::AbstractMatrix{T},
                                    i::Int, j::Int) where {T<:Real,T2,S1,S2}
    NA   = A.len
    NB   = B.len
    qB   = B.stencil_coefs
    midB = div(B.stencil_length, 2) + 1

    @assert( (NA, NB) == size(x) )

    sum_ij = zero(T)
    @fastmath @inbounds for jj in 1:B.stencil_length
        # imposing periodicity
        j_circ = 1 + mod(j - (midB-jj) - 1, NB)
        sum_i  = zero(T)
        @inbounds for ii in 1:NA
            sum_i += A[i,ii] * qB[jj] * x[ii,j_circ]
        end
        sum_ij += sum_i
    end

    sum_ij
end

function (A::FiniteDiffDeriv{T,1,T2,S1})(B::SpectralDeriv{T,2,S2}, x::AbstractMatrix{T},
                                         i::Int, j::Int) where {T<:Real,T2,S1,S2}
    NA   = A.len
    NB   = B.len
    qA   = A.stencil_coefs
    midA = div(A.stencil_length, 2) + 1

    @assert( (NA, NB) == size(x) )

    sum_ij = zero(T)
    @fastmath @inbounds for jj in 1:NB
        sum_i  = zero(T)
        @inbounds for ii in 1:A.stencil_length
            # imposing periodicity
            i_circ = 1 + mod(i - (midA-ii) - 1, NA)

            sum_i += qA[ii] * B[j,jj] * x[i_circ,jj]
        end
        sum_ij += sum_i
    end

    sum_ij
end
