
using Dates
using Printf

mutable struct TimeInfo{T<:Real}
    it  :: Int
    t   :: T
    dt  :: T
end
TimeInfo(it::Int, t::T, dt::T) where {T} = TimeInfo{T}(it, t, dt)
TimeInfo() = TimeInfo(0, 0.0, 0.0)

mutable struct Field{A,G}
    name  :: String
    data  :: A
    chart :: G
end
Field(name::String, data, chart::Chart) = Field{typeof(data),typeof(chart)}(name, data, chart)

function out_info(it::Integer, t::Real, time_per_hour::Real, f, label::String, info_every::Integer,
                  header_every::Integer)

    if it % header_every == 0
        println("-------------------------------------------------------------")
        println("Iteration      Time | Time per hour  |           $label")
        println("                    |                |   minimum      maximum")
        println("-------------------------------------------------------------")
    end

    if it % info_every == 0
        @printf "%9d %9.3f | %9.3f      | %9.4g    %9.4g\n" it t time_per_hour minimum(f) maximum(f)
    end

    nothing
end


struct Output{T}
    dir              :: String
    prefix           :: String
    every            :: Int
    software         :: String
    software_version :: String
    tinfo            :: TimeInfo{T}
    overwrite        :: Bool

    function Output{T}(dir::String, prefix::String, every::Int,
                       software::String, software_version::String, tinfo::TimeInfo{T};
                       overwrite::Bool=false) where {T}
        # if no name specified, use name of script
        if dir == ""
            dir = splitext(basename(Base.source_path()))[1]
        end

        # create folder if it doesn't exist already
        if !isdir(dir)
            mkdir(dir)
        end

        if prefix == ""
            prefix = "data_"
        end

        new(dir, prefix, every, software, software_version, tinfo, overwrite)
    end
end
function Output(dir::String, prefix::String, every::Int, tinfo::TimeInfo{T};
                overwrite::Bool=false) where {T<:Real}
    software         = "Jecco"
    software_version = "0.1.0"
    Output{T}(dir, prefix, every, software, software_version, tinfo;
              overwrite=overwrite)
end


output(param::Output, fields::Vararg{Field,N}) where {N} = output(param, [fields...])

# function output(param::Output, fields::Vector{Field{A,G}}) where {A,G}
function output(param::Output, fields::Vector)
    it = param.tinfo.it
    if it % param.every == 0
        filename = "$(param.prefix)$(lpad(string(it), 8, string(0))).h5"
        fullpath = abspath(param.dir, filename)

        if param.overwrite
            mode = "w"
        else
            mode = "cw"
        end
        # open file
        fid = h5open(fullpath, mode)

        # create openPMD structure
        grp = setup_openpmd_file(param, fid)

        for field in fields
            write_hdf5(param, grp, field)
        end

        # close file
        close(fid)
    end
    nothing
end

write_hdf5(param::Output, grp::HDF5Group, field::Field) =
    write_hdf5(param, grp, field.name, field.data, field.chart)

function write_hdf5(param::Output, grp::HDF5Group, fieldname::String, data::AbstractArray,
                    chart::Chart)
    # write actual data
    dset = write_dataset(grp, fieldname, data)
    setup_openpmd_mesh(dset, chart)

    nothing
end


function setup_openpmd_file(param::Output, fid::HDF5File)
    it   = param.tinfo.it
    time = param.tinfo.t
    dt   = param.tinfo.dt

    attrs(fid)["software"] = param.software
    attrs(fid)["softwareVersion"] = param.software_version
    attrs(fid)["openPMD"] = "1.1.0"
    attrs(fid)["openPMDextension"] = 0
    attrs(fid)["author"] = ENV["USER"]
    attrs(fid)["date"] = string(now())
    attrs(fid)["iterationEncoding"] = "fileBased"
    attrs(fid)["iterationFormat"] = "$(param.prefix)%T.h5"

    attrs(fid)["basePath"] = "/data/%T/"
    attrs(fid)["meshesPath"] = "fields/"

    grp = g_create(fid, "data/$it")

    attrs(grp)["time"] = time
    attrs(grp)["dt"] = dt

    g_create(grp, "fields")
end

function write_dataset(grp::HDF5Group, fieldname::String, data::AbstractArray)
    dset, = d_create(grp, fieldname, data)
    write(dset, data)
    dset
end

openpmd_geometry(coord::CartesianCoord) = "cartesian"
openpmd_geometry(coord::GaussLobattoCoord) = "other"

function openpmd_geometry(chart::Chart)
    geometries = [openpmd_geometry(coord) for coord in chart.coords]
    if all(geometries .== "cartesian")
        geometry = "cartesian"
    else
        geometry = "other"
    end
    geometry
end

function setup_openpmd_mesh(dset::HDF5Dataset, coord::AbstractCoord)
    attrs(dset)["geometry"]         = openpmd_geometry(coord)
    attrs(dset)["gridGlobalOffset"] = coord.min
    attrs(dset)["gridSpacing"]      = Jecco.delta(coord)
    attrs(dset)["gridMax"]          = coord.max
    attrs(dset)["gridType"]         = Jecco.coord_type(coord)
    attrs(dset)["axisLabels"]       = coord.name
    nothing
end

function setup_openpmd_mesh(dset::HDF5Dataset, chart::Chart)
    mins      = Jecco.min(chart)
    deltas    = Jecco.delta(chart)
    maxs      = Jecco.max(chart)
    gridtypes = Jecco.coord_type(chart)
    names     = Jecco.name(chart)

    attrs(dset)["geometry"]         = openpmd_geometry(chart)

    # Julia, like Fortran and Matlab, stores arrays in column-major order. HDF5
    # uses C's row-major order, and consequently every array's dimensions are
    # inverted compared to what is seen with tools like h5dump. This is the same
    # convention as for the Fortran and Matlab HDF5 interfaces. For consistency,
    # then, we here flip the order of the grid arrays (and remember to flip back
    # when reading data in). The advantage is that no data rearrangement takes
    # place when reading or writing the data itself, which is more intensive.
    attrs(dset)["gridGlobalOffset"] = mins[end:-1:1]
    attrs(dset)["gridSpacing"]      = deltas[end:-1:1]
    attrs(dset)["gridMax"]          = maxs[end:-1:1]
    attrs(dset)["gridType"]         = gridtypes[end:-1:1]
    attrs(dset)["axisLabels"]       = names[end:-1:1]
    nothing
end
