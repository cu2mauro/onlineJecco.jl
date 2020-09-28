using HDF5

abstract type AbstractTimeSeries{N,T} end

struct FieldTimeSeries{N,T} <: AbstractTimeSeries{N,T}
    ts     :: T
    field  :: String
end

# slightly adapted from openPMD-viewer
mutable struct OpenPMDTimeSeries{S}
    iterations        :: Array{Int64}
    files             :: Array{String}
    current_i         :: Int64
    current_iteration :: Int64
    current_t         :: Float64
    params            :: S
end

function OpenPMDTimeSeries(foldername::String, prefix::String)
    iterations, files = try
        list_h5_files(foldername, prefix=prefix)
    catch e
        if isa(e, SystemError) && e.errnum == 2 # "No such file or directory"
            throw(ErrorException("No files found."))
        else
            throw(e)
        end
    end

    if length(iterations) == 0
        throw(ErrorException("No files found."))
    end

    # open first file to extract parameters
    fid    = h5open(files[1], "r")
    it     = iterations[1]
    grp, t = read_openpmd_file(fid, it)

    # read group attributes
    params = read_group_attributes(grp)

    OpenPMDTimeSeries{typeof(params)}(iterations, files, 1, it, t, params)
end

"""
    OpenPMDTimeSeries(foldername::String; prefix::String="")

Initialize an openPMD time series, ie, scan the directory and extract the
openPMD files starting with the given prefix (can be left empty)

# Example
```
julia> ts = OpenPMDTimeSeries("./data"; prefix="wave_")
```
"""
OpenPMDTimeSeries(foldername::String; prefix::String="") =
    OpenPMDTimeSeries(foldername, prefix)


FieldTimeSeries{N}(ts::OpenPMDTimeSeries, field::String) where{N} =
    FieldTimeSeries{N,typeof(ts)}(ts, field)

"""
    FieldTimeSeries(foldername::String; prefix::String, field::String)

Initialize a (openPMD) time series for the given `N`-dimensional `field`, ie,
scan the directory and extract the openPMD files starting with the given
`prefix`. The data corresponding to the given `field` will then be extracted
from the corresponding hdf5 file when requested.

# Example
```
julia> xi_ts = FieldTimeSeries("./", prefix="gauge_", field="xi")
```
"""
function FieldTimeSeries(foldername::String; prefix::String, field::String)
    ts = OpenPMDTimeSeries(foldername, prefix)
    f, chart = get_field(ts, it=1, field=field)
    N = ndims(chart)
    FieldTimeSeries{N}(ts, field)
end

function Base.getindex(ff::FieldTimeSeries, a::Int, idx::Vararg)
    it = ff.ts.iterations[a]
    f, chart = get_field(ff.ts, it=it, field=ff.field)
    t = ff.ts.current_t
    t, chart[idx], f[idx]
end


function list_h5_files(foldername::String; prefix::String="")
    path     = abspath(foldername)
    allfiles = readdir(path)

    Ns = length(prefix)

    its_names = Tuple[]
    # append only the files whose names start with the given prefix
    for file in allfiles
        try
            if (file[1:Ns] == prefix && (file[end-2:end] == ".h5" ||
                                         file[end-4:end] == ".hdf5"))
                fullname = joinpath(path, file)
                # extract all iterations from the file
                fid      = h5open(fullname, "r")
                its      = names(fid["/data"])
                close(fid)
                # for each iteration add to list of tuples with iteration and
                # name
                for it in its
                    push!(its_names, (parse(Int64, it), fullname))
                end
            end
        catch ex
            if isa(ex, BoundsError)
                # probably triggered by string comparison; do nothing
            else
                throw(ex)
            end
        end
    end

    # sort according to iteration
    sort!(its_names)
    # and extract the list of filenames and iterations
    filenames = [name for (it, name) in its_names]
    its       = [it for (it, name) in its_names]

    (its, filenames)
end

"""
    get_field(ts::OpenPMDTimeSeries; it::Int, field::String)

Given a time series, extract the requested field (and corresponding chart) from
an HDF5 file in the openPMD format. As side-effects, ```ts.current_i```,
```ts.current_iteration``` and ```ts.current_t``` are correspondingly modified.

# Example
```
julia> psi, chart=get_field(ts, it=20, field="psi");

julia> ts.current_t
20.0

julia> ts.current_iteration
20

julia> ts.current_i
21

```
"""
function get_field(ts::OpenPMDTimeSeries; it::Int, field::String, verbose::Bool=false)
    # index that corresponds to the closest iteration requested
    ts.current_i = argmin(abs.(it .- ts.iterations))
    # the closest iteration found (it need not be the requested one)
    ts.current_iteration = ts.iterations[ts.current_i]
    # and corresponding file
    filename = ts.files[ts.current_i]

    if verbose
        println("Reading file $filename")
    end
    # open file
    fid = h5open(filename, "r")

    # read in openPMD structure
    grp, ts.current_t = read_openpmd_file(fid, ts.current_iteration)

    # read actual data
    data, chart = read_dataset(grp, field)

    # close file
    close(fid)

    data, chart
end

function read_openpmd_file(fid::HDF5File, it::Integer)
    basePath   = read(attrs(fid)["basePath"])
    basePath   = replace(basePath, "%T" => it)
    meshesPath = read(attrs(fid)["meshesPath"])

    # pointer to base group (ie, with the information for the requested time
    # level) within the given hdf5 file
    grp_base = fid[basePath]

    time = read(attrs(grp_base)["time"])

    # pointer to mesh group (with the actual chart function data)
    grp_mesh = grp_base[meshesPath]

    grp_mesh, time
end

function read_group_attributes(grp::HDF5Group)
    grp_attrs = attrs(grp)
    keys      = names(grp_attrs)
    vals      = read.(Ref(grp_attrs), keys)
    Dict(keys[i] => vals[i] for i in 1:length(keys))
end

function read_dataset(grp::HDF5Group, var::String)
    dset       = grp[var]
    dset_attrs = attrs(dset)

    func  = read(dset)
    nodes = size(func)
    T     = eltype(func)
    dim_  = length(nodes)

    if dim_ == 1
        names         = read(dset_attrs["axisLabels"])
        mins          = read(dset_attrs["gridGlobalOffset"])
        maxs          = read(dset_attrs["gridMax"])
        gridtypes     = read(dset_attrs["gridType"])
    else
        # remember to flip the order since HDF5 uses row-major order to store
        # arrays, as opposed to Julia's column-major order
        names         = read(dset_attrs["axisLabels"])[end:-1:1]
        mins          = read(dset_attrs["gridGlobalOffset"])[end:-1:1]
        maxs          = read(dset_attrs["gridMax"])[end:-1:1]
        gridtypes     = read(dset_attrs["gridType"])[end:-1:1]
    end

    chart = Chart(gridtypes, names, mins, maxs, nodes)

    func, chart
end
