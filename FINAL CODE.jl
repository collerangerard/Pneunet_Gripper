# ====================================================================
# CONTENTS
# 1  FRAMEWORK SETTINGS
# 2  IMPORT LIBRARIES
# 3  SETUP
# 4  PNEUNET GEOMETRY PARAMETERS (FOR SIMULATION AND PRINTING/MOULDING)
# 5  STL GEOMETRY PARAMETERS (FOR PRINTING/MOULDING)
# 6  GEOMETRY HELPER FUNCTIONS
# 7  FILE OUTPUT FUNCTIONS
# 8  GEOMETRY CREATION FUNCTIONS
# 9  FEBio SIMULATION FUNCTIONS
# 10 STL CREATION FUNCTIONS
# 11 GEOMETRY CREATION SCRIPT
# 12 FEBio SIMULATION SCRIPT
# 13 GLMakie plot script
# 14 VISUALIZATION SCRIPT (ADJUSTABLE PARAMETERS)
# 15 STL CREATION SCRIPT
# ====================================================================

# ====================================================================
# 1 FRAMEWORK SETTINGS
runSimulation = 1   # creates .feb file for FEBio
runFEBio = 1        # submits .feb file to FEBio
gravitySim = 1      # includes gravity in simulation
paper = 0           # includes 2D shell elements in strain limiting layer to simulate paper
outputExcel = 1     # outputs displacements and bend angle of the end edges of pneunet
runPlot = 0         # visualizes pneunet geometry using GLMakie
visualSlider = 0    # visualizes pneunet with adjustable parameters
outputStl = 1       # outputs connector, pneunet and moulds as stls
# ====================================================================

# ====================================================================
# 2 IMPORT LIBRARIES
using Comodo
using Comodo.GLMakie
using Comodo.GeometryBasics
using Comodo.Statistics
using Comodo.LinearAlgebra
using FileIO
using FEBio
using FEBio.XML
using Printf
using XLSX
# ====================================================================

# ====================================================================
# 3 SETUP
GLMakie.closeall()          # closes all open GLMakie windows
const FEBIO_EXEC = "febio4" # FEBio executable

# Setup variables
number = 1.00   # File number (can be used to differentiate different simulations)
P = 0.02        # Target inflation pressure [MPa]

# Saving options names
saveDir = joinpath(pwd(), "Simulations")            # Main directory to save FEBio input and output files (in current working directory)
filename = @sprintf("Simulation_%.2f", number)    # Filname with file number to 2 decimal places 
# ====================================================================

# ====================================================================
# 4 PNEUNET GEOMETRY PARAMETERS (FOR SIMULATION AND PRINTING/MOULDING)
pointSpacing = 1.5  # Approximate element size
n_chambers = 6      # Number of chambers including start and end

# X-direction (lengths) in Float64
l_first_chamber = 12.0  # Length of the very first chamber
l_first_wall = 5.0      # Thickness of the first wall
l_gaps = 1.0            # Length of the channel gap between chambers
l_chambers = 12.0       # Length of each repeated chamber
l_walls = 2.0           # Thickness of each repeated wall
l_end_wall = 5.0        # Thickness of the final wall
l_end_chamber = 12.0    # Length of the last chamber

# Z-direction (heights) in Float64
h_full = 25.0                           # Full height of the pneunet
h_base = 3.0                            # Thickness of the strain-limiting base layer
h_floor_gap = 8.0                       # Height of the channel floor gap
h_ceiling_channel = h_floor_gap - 2.0   # Height of the channel ceiling
h_ceiling_chamber = h_full - 5.0        # Height of the chamber ceiling
h_sll = 3.0                             # Height of the strain limiting layer  

# Y-direction (depths) in Float64
d_full = 25.0   # Total depth of the pneunet
d_side = 5.0    # Side wall depth
# ====================================================================

# ====================================================================
# 5 STL GEOMETRY PARAMETERS (FOR PRINTING/MOULDING)
pointSpacing_stl = 1.5  # Approximate face size
t_mould = 5.0           # thickness of outer walls of moulds

# Radius of holes and shafts (connector)
r_hole1 = 1.9 / 2.0     # hole through centre
r_shaft3 = 3.5 / 2.0    # shaft between main part pipe connection bite
r_bite4 = 4.8 / 2.0     # widest part of bite
r_point5 = r_shaft3     # flat top face of bite equal to shaft

# Heights (connector)
h_connector_inset = l_first_wall    # thickness (height) part which inserts into open face of pneunet
h_connector2 = 5.0                  # thickness (height) of part from outer flat face of connector and start of pneunet
h_shaft3 = 4.5                      # height of shaft section
h_bite4 = 1.0                       # height of flat part of bite
h_loft5 = 5.5                       # height of loft part of bite (to end)

# Dimensions of holes and pins in moulds
r_hole = 1.75  # Radius of hole
r_pin = 1.5    # Radius of pin
d_hole = 1.75  # Depth of hole
d_pin = 1.5    # Depth of pin
# ====================================================================

# ====================================================================
# 6 GEOMETRY HELPER FUNCTIONS
"""
    function find_faces_at_z(faces, vertices, z_target; atol=1e-6)

Finds faces where ALL vertices have z-coordinate ≈ z_target.

# Arguments
- `faces`: Vector of face indices (works for tri3 and tri6)
- `vertices`: Vector of vertex coordinates used by faces
- `z_target`: Target z-coordinate
- `atol`: Tolerance in comparison, default is 1e-6

# Returns
Vector of faces
"""
function find_faces_at_z(faces, vertices, z_target; atol=1e-6)
    result = similar(faces, 0) # create empty vector of same type as faces
    sizehint!(result, length(faces) ÷ 10)  # Pre-allocate a guess size
    for (i, face) in enumerate(faces) # cycle through all faces
        if all(isapprox(vertices[v][3], z_target; atol=atol) for v in face) # check if z-coordinat of each vertex is approx equal to z_target
            push!(result, faces[i]) # if criterion met, add faces to result
        end
    end
    return result # vector of faces 
end

"""
    find_faces_at_x(faces, vertices, x_target; atol=1e-6)

Finds faces where ALL vertices have x-coordinate ≈ x_target.

# Arguments
- `faces`: Vector of face indices (works for tri3 and tri6)
- `vertices`: Vector of vertex coordinates used by faces
- `x_target`: Target x-coordinate, default is 1e-6
- `atol`: Tolerance in comparison

# Returns
Vector of faces
"""
function find_faces_at_x(faces, vertices, x_target; atol=1e-6)
    result = similar(faces, 0) # create empty vector of same type as faces
    sizehint!(result, length(faces) ÷ 10)  # Pre-allocate a guess size
    for (i, face) in enumerate(faces) # cycle through all faces
        if all(isapprox(vertices[v][1], x_target; atol=atol) for v in face) # check if z-coordinat of each vertex is approx equal to z_target
            push!(result, faces[i]) # if criterion met, add faces to result
        end
    end
    return result # vector of faces 
end

"""
    unique_vertices_hash(V1, V2; tol)

Merges 2 vectors of vertices into 1 vector, removing duplicates, using spatial hashing

# Arguments
- 'V1': first vector of vertices 
- 'V2': second vector of vertices 
- 'tol': tolerance (default set to 1e-6) 

# Returns
- 'Vunique': vector of unique vertices
- 'indUnique': indices of unique vertices from concatenated input vectors
- 'indMap': mapping from each input vertex to its corresponding output vertex
"""
function unique_vertices_hash(V1, V2; tol=1e-6)
    V = vcat(V1, V2) # combined both vectors
    lengthV = length(V) # find length of concatenated vector

    table = Dict{NTuple{3,Int},Int}() # Hash table, 3 dimensions

    Vunique = Point{3,Float64}[] # initialise unique point
    indUnique = Int[] # initialise unique index
    indMap = zeros(Int, lengthV) # initialise mapping length of concatenated vector

    invtol = 1 / tol # inverse of tolerance for easier reading

    for i in 1:lengthV # cycle through full length of concatenated vector
        p = V[i] # take vertex i

        # Assign key coordinate by rounding p/tol
        key = (round(Int, p[1] * invtol),   # x-coordinate
            round(Int, p[2] * invtol),      # y-coordinate
            round(Int, p[3] * invtol))      # z-coordinate

        if haskey(table, key) # if key seen before
            indMap[i] = table[key] # map to existing unique vertex
        else # New unique vertex
            push!(Vunique, p)       # create unique vertex
            push!(indUnique, i)     # create unique index
            idx = length(Vunique)   # position of new vertex in vector of unique vertices 
            table[key] = idx        # record vertex position in table for given key coordinate
            indMap[i] = idx         # create map of old vertex to new vertex
        end
    end

    return Vunique, indUnique, indMap # vector of vertices, vector of indices, vector of indices
end

"""
    reorder_tri6_febio(face::NTuple{6,Int}, nodes)

Reorders a TetGen tri6 face into FEBio order

# Arguments
- 'face': a tri6 face
- 'nodes': a vector of verticex, which face belongs to

# Returns
A reordered tri6 face
"""
function reorder_tri6_febio(face::NTuple{6,Int}, nodes)
    n1, n2, n3 = face[1], face[3], face[5] # Corner nodes
    mids = [face[2], face[4], face[6]] # Mid-edge nodes (unordered)

    # Helper function: squared distance between two nodes
    dist2(a, b) = sum((nodes[a] .- nodes[b]) .^ 2)

    # Edge 1-4-2
    d12 = [dist2(m, n1) + dist2(m, n2) for m in mids] # sum of distances between each edge node and corner nodes 1 and 2
    idx12 = argmin(d12) # index of smallest distance
    n4 = mids[idx12] # node 4
    deleteat!(mids, idx12) # remove node 4 from list

    # Edge 2-5-3
    d23 = [dist2(m, n2) + dist2(m, n3) for m in mids] # sum of distances between each edge node and corner nodes 2 and 3
    idx23 = argmin(d23) # index of smallest distance
    n5 = mids[idx23] # node 5
    deleteat!(mids, idx23) # remove node 5 from list

    # Edge 3-6-1
    n6 = mids[1] # Only one midpoint left

    return (n1, n2, n3, n4, n5, n6) # reordered tri6 face
end

"""
    reorder_rectangular_boundary(points::Vector{Point{3,Float64}}, plane::Symbol)

Reorders vector of vertices clockwise using the arctan function, for unordered rectangle vectors

# Arguments
- 'points': A rectangulernvector of unordered vertices
- 'plane': Symbol denoting which plan the rectangle is parallel to (':xy', ':xz' or ':yz')

# Returns
Vector of vertices tracing the perimeter of a rectangle clockwise
"""
function reorder_rectangular_boundary(points::Vector{Point{3,Float64}}, plane::Symbol)
    tolerance = 1e-6 # tolerance for duplicate points
    unique_points = Point{3,Float64}[] # initialize vector of unique vertices

    for p in points # cycle through all points, checking for uniqueness
        if !any(isapprox.(p[1], unique_points[i][1], atol=tolerance) && # x-coordinate
                isapprox.(p[2], unique_points[i][2], atol=tolerance) && # y-coordinate
                isapprox.(p[3], unique_points[i][3], atol=tolerance)    # z-coordinate
                for i in 1:length(unique_points)) # cycle through existing vector of unique vertices, not any vertices the same
            push!(unique_points, p) # if unique, add to vector of unique vertices
        end
    end

    # Check which plane to use, assign which coordinates to use
    coord1_idx, coord2_idx = if plane == :xy
        1, 2
    elseif plane == :xz
        1, 3
    elseif plane == :yz
        2, 3
    end

    center = sum(unique_points) / length(unique_points) # Compute the center of all verticex in unique points

    # Calculate angle of each point relative to center on the specified plane, using arctan functions
    angles = [atan(unique_points[i][coord2_idx] - center[coord2_idx],
        unique_points[i][coord1_idx] - center[coord1_idx])
              for i in 1:length(unique_points)]

    # Find the bottom left corner based on plane
    min_c1 = minimum(p[coord1_idx] for p in unique_points) # minimum coordinate 1
    min_c2 = minimum(p[coord2_idx] for p in unique_points) # minimum coordinate 2

    # Find the index of point closest to bottom-left corner (min_c1, min_c2)
    _, bl_idx = findmin([(unique_points[i][coord1_idx] - min_c1)^2 +
                         (unique_points[i][coord2_idx] - min_c2)^2
                         for i in 1:length(unique_points)]) # check all points in unique_points

    bl_angle = angles[bl_idx] # Angle of the bottom left point to set to 0

    adjusted_angles = [(a - bl_angle + 2π) % (2π) for a in angles] # adjust angles of points based on bottom left point to set to 0, keeping clockwise order

    sorted_indices = sortperm(adjusted_angles) # Sort points by adjusted angle

    ordered = unique_points[sorted_indices] # Reorder points starting from bottom left corner

    return ordered # vector of vertices tracing rectangular boundary, clockwise
end
# ====================================================================

# ====================================================================
# 7 FILE OUTPUT FUNCTIONS

"""
    export_vectors_to_excel(filename::AbstractString,
    θ_deg,
    top_tip_mean_coord_xz,
    bottom_tip_mean_coord_xz,
    top_tip_mean_disp_xz,
    bottom_tip_mean_disp_xz,
    times,
    P)

Creates excel file with position and displacement of top and bottom end edges of pneunet, angle to vertical of end face, simulation time and pressure


# Arguments
- 'filename': Abstract string which the file is called
- 'θ_deg': angle of end face to vertical, measured clockwise
- 'top_tip_mean_coord_xz': mean coordinate of top edge
- 'bottom_tip_mean_coord_xz': mean coordinate of bottom edge
- 'top_tip_mean_disp_xz': mean displacement of top edge
- 'bottom_tip_mean_disp_xz': mean displacement of bottom edge
- 'times': simulation time
- 'P': pressure

# Returns

"""

function export_vectors_to_excel(filename::AbstractString,
    θ_deg,
    top_tip_mean_coord_xz,
    bottom_tip_mean_coord_xz,
    top_tip_mean_disp_xz,
    bottom_tip_mean_disp_xz,
    times,
    P)

    XLSX.openxlsx(filename, mode="w") do xf # Create excel file
        sheet = xf[1] # write on first sheet

        # header names
        headers = ["step", "time", "pressure", "θ_deg",
            "top_tip_mean_coord_x", "top_tip_mean_coord_z",
            "bottom_tip_mean_coord_x", "bottom_tip_mean_coord_z",
            "top_tip_mean_disp_x", "top_tip_mean_disp_z",
            "bottom_tip_mean_disp_x", "bottom_tip_mean_disp_z"]

        # assign headers to 1st row of each column
        for (j, h) in enumerate(headers)
            sheet[XLSX.CellRef(1, j)] = h
        end

        # data rows
        n = length(θ_deg) # length of data (constant for all as linked to time steps in simulation)
        for i in 1:n # cycle through length of data and input
            sheet[XLSX.CellRef(i + 1, 1)] = i                # step number
            sheet[XLSX.CellRef(i + 1, 2)] = times[i]         # step time
            sheet[XLSX.CellRef(i + 1, 3)] = max(0, P * (times[i] - 1))     # pressure
            sheet[XLSX.CellRef(i + 1, 4)] = θ_deg[i] # angle of end face to vertical, measured clockwise

            sheet[XLSX.CellRef(i + 1, 5)] = top_tip_mean_coord_xz[i][1] # mean x-coordinate of top edge
            sheet[XLSX.CellRef(i + 1, 6)] = top_tip_mean_coord_xz[i][2] # mean z-coordinate of top edge

            sheet[XLSX.CellRef(i + 1, 7)] = bottom_tip_mean_coord_xz[i][1] # mean x-coordinate of bottom edge
            sheet[XLSX.CellRef(i + 1, 8)] = bottom_tip_mean_coord_xz[i][2] # mean z-coordinate of bottom edge

            sheet[XLSX.CellRef(i + 1, 9)] = top_tip_mean_disp_xz[i][1] # mean x-displacement of top edge
            sheet[XLSX.CellRef(i + 1, 10)] = top_tip_mean_disp_xz[i][2] # mean z-displacement of top edge

            sheet[XLSX.CellRef(i + 1, 11)] = bottom_tip_mean_disp_xz[i][1] # mean x-displacement of bottom edge
            sheet[XLSX.CellRef(i + 1, 12)] = bottom_tip_mean_disp_xz[i][2] # mean z-displacement of bottom edge
        end
    end
end

"""
    write_stl_ascii(filename::AbstractString,
    vertices::AbstractVector{<:Point{3,<:Real}},
    faces::AbstractVector{<:NgonFace};
    solid_name::AbstractString="mesh")

Creates .stl file of input geometry (vertices and faces)

# Arguments
- 'filename': Abstract string which the file is called
- 'vertices': A vector of vertices
- 'faces': A vector of faces which correspond to 'vertices', must be tri3
- 'solid_name': Abstract string which is the stl header, default set as "mesh"

# Returns

"""

function write_stl_ascii(filename::AbstractString,
    vertices::AbstractVector{<:Point{3,<:Real}},
    faces::AbstractVector{<:NgonFace};
    solid_name::AbstractString="mesh")

    # Ensure output directory exists
    outdir = dirname(filename) # directory path
    isdir(outdir) || mkpath(outdir) # is directory or creates directory

    open(filename, "w") do io # Open file for writing, automatically closes when block ends)
        println(io, "solid $solid_name") # Header line

        fmt(x) = Printf.@sprintf("% .6e", Float64(x)) # Helper function writes formated numbers in scientific notation

        for f in faces # loops over each face
            i1, i2, i3 = collect(f)  # indices of the face

            # Lookup vertices
            p1 = vertices[i1]
            p2 = vertices[i2]
            p3 = vertices[i3]
            # convert to Vec type
            v1 = Vec(p1)
            v2 = Vec(p2)
            v3 = Vec(p3)
            n = cross(v2 - v1, v3 - v1) # find facet normal using cross-product
            if norm(n) < eps(Float64) # zero area triangle
                nx, ny, nz = (0.0, 0.0, 0.0)
            else # positive area triangle
                n = n / norm(n)
                nx, ny, nz = Float64.(n)
            end
            # co-ordinates as Float64
            x1, y1, z1 = Float64.(v1)
            x2, y2, z2 = Float64.(v2)
            x3, y3, z3 = Float64.(v3)
            # Write facet
            println(io, "  facet normal $(fmt(nx)) $(fmt(ny)) $(fmt(nz))")
            println(io, "    outer loop")
            println(io, "      vertex $(fmt(x1)) $(fmt(y1)) $(fmt(z1))")
            println(io, "      vertex $(fmt(x2)) $(fmt(y2)) $(fmt(z2))")
            println(io, "      vertex $(fmt(x3)) $(fmt(y3)) $(fmt(z3))")
            println(io, "    endloop")
            println(io, "  endfacet")
        end

        # end of stl
        println(io, "endsolid $solid_name")
    end

    return nothing
end
# ====================================================================

# ====================================================================
# 8 GEOMETRY CREATION FUNCTIONS
"""
    build_boundaries(
    pointSpacing,        
    n_chambers,  
    h_full,              
    h_base,              
    h_ceiling_channel,   
    h_floor_gap, 
    h_ceiling_chamber,  
    l_first_chamber, 
    l_first_wall, 
    l_gaps,  
    l_chambers,   
    l_walls,       
    l_end_wall,  
    l_end_chamber,   
    d_full,
    d_side  
)

Creates inner and outer boundaries fo pneunet geometry

# Returns
Inner and outer boundaries as vector of vertices, length of pneunet as float
"""
function build_boundaries(
    pointSpacing,
    n_chambers,
    h_full,
    h_base,
    h_ceiling_channel,
    h_floor_gap,
    h_ceiling_chamber,
    l_first_chamber,
    l_first_wall,
    l_gaps,
    l_chambers,
    l_walls,
    l_end_wall,
    l_end_chamber,
    d_full,
    d_side
)

    l_pneunet = l_first_chamber + l_gaps * (n_chambers - 1) + l_chambers * (n_chambers - 2) + l_end_chamber # length of pneunet

    # --- First chamber outer ---
    V_first_chamber_outer = [
        Point{3,Float64}(0.0, 0.0, 0.0),
        Point{3,Float64}(0.0, 0.0, h_full),
        Point{3,Float64}(l_first_chamber, 0.0, h_full),
        Point{3,Float64}(l_first_chamber, 0.0, h_floor_gap),
        Point{3,Float64}(l_first_chamber + l_gaps, 0.0, h_floor_gap),
    ]
    V_corners_outer = copy(V_first_chamber_outer)

    # --- First chamber inner ---
    V_first_chamber_inner = [
        Point{3,Float64}(l_first_wall, 0.0, h_base),
        Point{3,Float64}(l_first_wall, 0.0, h_ceiling_chamber),
        Point{3,Float64}(l_first_chamber - l_walls, 0.0, h_ceiling_chamber),
        Point{3,Float64}(l_first_chamber - l_walls, 0.0, h_ceiling_channel),
        Point{3,Float64}(l_first_chamber + l_gaps + l_walls, 0.0, h_ceiling_channel),
    ]
    V_corners_inner = copy(V_first_chamber_inner)

    # --- Repeated chambers ---
    for i ∈ 1:(n_chambers-2)
        offset_outer = V_first_chamber_outer[end][1] + (Float64(i - 1) * (l_chambers + l_gaps))
        V_repeated_chambers_outer = [
            Point{3,Float64}(offset_outer, 0.0, h_full),
            Point{3,Float64}(offset_outer + l_chambers, 0.0, h_full),
            Point{3,Float64}(offset_outer + l_chambers, 0.0, h_floor_gap),
            Point{3,Float64}(offset_outer + l_chambers + l_gaps, 0.0, h_floor_gap),
        ]
        append!(V_corners_outer, V_repeated_chambers_outer)

        offset_inner = offset_outer + l_walls
        V_repeated_chambers_inner = [
            Point{3,Float64}(offset_inner, 0.0, h_ceiling_chamber),
            Point{3,Float64}(offset_inner + l_chambers - 2 * l_walls, 0.0, h_ceiling_chamber),
            Point{3,Float64}(offset_inner + l_chambers - 2 * l_walls, 0.0, h_ceiling_channel),
            Point{3,Float64}(offset_inner + l_chambers + l_gaps, 0.0, h_ceiling_channel),
        ]
        append!(V_corners_inner, V_repeated_chambers_inner)
    end

    # --- Last chamber outer ---
    V_last_chamber_outer = [
        Point{3,Float64}(V_corners_outer[end][1], 0.0, h_full),
        Point{3,Float64}(V_corners_outer[end][1] + l_end_chamber, 0.0, h_full),
        Point{3,Float64}(V_corners_outer[end][1] + l_end_chamber, 0.0, 0.0),
    ]
    append!(V_corners_outer, V_last_chamber_outer)

    # --- Last chamber inner ---
    V_last_chamber_inner = [
        Point{3,Float64}(V_corners_inner[end][1], 0.0, h_ceiling_chamber),
        Point{3,Float64}(V_corners_inner[end][1] + l_end_chamber - l_walls - l_end_wall, 0.0, h_ceiling_chamber),
        Point{3,Float64}(V_corners_inner[end][1] + l_end_chamber - l_walls - l_end_wall, 0.0, h_base)
    ]
    append!(V_corners_inner, V_last_chamber_inner)

    # --- Interpolate points ---
    must_points_outer = collect(1:length(V_corners_outer))
    V_boundary_outer = evenly_space(V_corners_outer, pointSpacing;
        close_loop=true, spline_order=2,
        must_points=must_points_outer)

    must_points_inner = collect(1:length(V_corners_inner))
    V_boundary_inner = evenly_space(V_corners_inner, pointSpacing;
        close_loop=true, spline_order=2,
        must_points=must_points_inner)

    return V_boundary_inner, V_boundary_outer, l_pneunet # Vectors of vertices, float 
end


"""
    extrude_boundaries(V_boundary_inner, V_boundary_outer, d_full, d_side, pointSpacing)

Extrudes inner and outer boundaries to create surfaces as sets of tri3 faces.

# Returns
Faces and corresponding vertices of extruded surfaces
"""
function extrude_boundaries(V_boundary_inner, V_boundary_outer, d_full, d_side, pointSpacing)

    # Extrusion vector in Y-direction
    n = Vec3{Float64}(0.0, 1.0, 0.0)

    # --- Outer extrusion ---
    num_steps_width = 1 + ceil(Int, d_full / pointSpacing) # minimum of 2 layers
    F_extrude_outer, V_extrude_outer = extrudecurve(
        V_boundary_outer;
        extent=d_full,
        direction=:both,
        n=n,
        num_steps=num_steps_width,
        close_loop=true,
        face_type=:forwardslash # triangle faces
    )

    # --- Inner extrusion ---
    num_steps_width_inner = 1 + ceil(Int, (d_full - d_side) / pointSpacing) # minimum of 2 layers
    F_extrude_inner, V_extrude_inner = extrudecurve(
        V_boundary_inner;
        extent=d_full - 2.0 * d_side,
        direction=:both,
        n=n,
        num_steps=num_steps_width_inner,
        close_loop=true,
        face_type=:forwardslash # triangle faces
    )

    F_extrude_inner = [reverse(f) for f in F_extrude_inner] # Flip inner faces so normals point outward

    return F_extrude_inner, V_extrude_inner, F_extrude_outer, V_extrude_outer # faces and corresponding vertices of extruded surfaces
end


"""
    build_endcaps(V_boundary_inner, V_boundary_outer, d_full, d_side, pointSpacing, h_floor_gap, h_ceiling_channel)

Creates surfaces at ends of extrused surfaces to close off pneunet shape, uses regiontrimesh

# Returns
Faces and corresponding vertices of endcap surfaces
"""
function build_endcaps(V_boundary_inner, V_boundary_outer, d_full, d_side, pointSpacing, h_floor_gap, h_ceiling_channel)
    # Project boundaries into x–z plane
    V_xy_outer = [Point{3,Float64}(p[1], p[3], 0.0) for p in V_boundary_outer]
    V_xy_inner = [Point{3,Float64}(p[1], p[3], 0.0) for p in V_boundary_inner]

    # Reverse orientation for triangulation
    V_xy_reversed_outer = (reverse(V_xy_outer),) # in form acceptable for regiontrimesh
    V_xy_reversed_inner = (reverse(V_xy_inner),) # in form acceptable for regiontrimesh
    R = ([1],) # regions for regiontrimesh

    # Triangulate outer and inner regions
    F_outer, V_tri_outer = regiontrimesh(V_xy_reversed_outer, R, pointSpacing)
    F_inner, V_tri_inner = regiontrimesh(V_xy_reversed_inner, R, pointSpacing)

    # Back faces, same indices as front faces
    F_back_outer = copy(F_outer)
    F_back_inner = copy(F_inner)

    # Front faces (reverse orientation)
    F_front_inner = [reverse(f) for f in F_back_inner]
    F_front_outer = [reverse(f) for f in F_back_outer]

    # Position vertices in 3D space
    V_back_outer = [Point{3,Float64}(p[1], d_full / 2.0, p[2]) for p in V_tri_outer]
    V_front_outer = [Point{3,Float64}(p[1], -d_full / 2.0, p[2]) for p in V_tri_outer]
    V_back_inner = [Point{3,Float64}(p[1], d_full / 2.0 - d_side, p[2]) for p in V_tri_inner]
    V_front_inner = [Point{3,Float64}(p[1], -d_full / 2.0 + d_side, p[2]) for p in V_tri_inner]

    return F_back_outer, V_back_outer, F_front_outer, V_front_outer, F_back_inner, V_back_inner, F_front_inner, V_front_inner
end

"""
    build_main_body(F_extrude_outer, V_extrude_outer,
    F_extrude_inner, V_extrude_inner,
    F_back_outer, V_back_outer,
    F_front_outer, V_front_outer,
    F_back_inner, V_back_inner,
    F_front_inner, V_front_inner,
    l_first_wall, l_first_chamber, l_walls,
    h_base, h_ceiling_chamber)

Creates finite element mesh of pneunet geometry, using tengenmesh
Elements are Tet10

# Returns
Elements, corresponding vertices, element sets, boundary faces and face sets
"""
function build_main_body(F_extrude_outer, V_extrude_outer,
    F_extrude_inner, V_extrude_inner,
    F_back_outer, V_back_outer,
    F_front_outer, V_front_outer,
    F_back_inner, V_back_inner,
    F_front_inner, V_front_inner,
    l_first_wall, l_first_chamber, l_walls,
    h_base, h_ceiling_chamber)

    # --- Join all geometry parts ---
    Fs, Vs, Cs = joingeom(F_extrude_outer, V_extrude_outer,
        F_extrude_inner, V_extrude_inner,
        F_back_outer, V_back_outer,
        F_front_outer, V_front_outer,
        F_back_inner, V_back_inner,
        F_front_inner, V_front_inner)

    # --- Merge duplicate vertices ---
    Fs, Vs = mergevertices(Fs, Vs)

    # --- Define region and hole points ---
    V_regions = [Point{3,Float64}(l_first_wall / 2.0, 0.0, h_base / 2.0)]
    V_holes = [Point{3,Float64}(l_first_wall + ((l_first_chamber - l_first_wall - l_walls) / 2.0),
        0.0,
        h_base + ((h_ceiling_chamber - h_base) / 2.0))]

    # --- TetGen options ---
    stringOpt = "pqAYQ"
    element_type = Tet10{Int}

    # --- Run TetGen meshing ---
    E, V, CE, Fb, Cb = tetgenmesh(Fs, Vs;
        facetmarkerlist=Cs,
        V_regions=V_regions,
        V_holes=V_holes,
        stringOpt=stringOpt,
        element_type=element_type)

    return E, V, CE, Fb, Cb # Elements, corresponding vertices, element sets, boundary faces and face sets
end


"""
    build_sll_mesh(F_extrude_outer, V_extrude_outer, h_sll, d_full, l_pneunet, pointSpacing)

Creates geometry and finite element mesh of strain limiting layer, using regiontrimesh and tetgenmesh. 
Elements are Tet10. 
Copies faces at bottom of pneunet main body. 
Creates new boundary curve and extrudes downwards. 
Regiontrimesh closes off bottom. 
Tetgenmesh meshes shape

# Returns
Elements, corresponding vertices, element sets, boundary faces and face sets
"""
function build_sll_mesh(F_extrude_outer, V_extrude_outer, h_sll, d_full, l_pneunet, pointSpacing)
    # Identify bottom faces (z ≈ 0.0) 
    F_bottom_faces = find_faces_at_z(F_extrude_outer, V_extrude_outer, 0.0; atol=1e-6)

    # Outline of strain limiting layer boundary at z=0.0
    V_bottom_outline_corners = [
        Point{3,Float64}(0.0, d_full / 2.0, 0.0),
        Point{3,Float64}(0.0, -d_full / 2.0, 0.0),
        Point{3,Float64}(l_pneunet, -d_full / 2.0, 0.0),
        Point{3,Float64}(l_pneunet, d_full / 2.0, 0.0),
    ]

    # Interpolate boundary
    must_points = collect(1:length(V_bottom_outline_corners))
    V_bottom_outline = evenly_space(V_bottom_outline_corners, pointSpacing;
        close_loop=true, spline_order=2,
        must_points=must_points)

    n = Vec3{Float64}(0.0, 0.0, 1.0)

    # --- Outer extrusion ---
    num_steps_width = max(3, ceil(Int, h_sll / pointSpacing)) # minimum of 3
    F_extrude_sll, V_extrude_sll = extrudecurve(
        V_bottom_outline;
        extent=h_sll,
        direction=:negative,
        n=n,
        num_steps=num_steps_width,
        close_loop=true,
        face_type=:forwardslash
    )

    # bottom sll
    V_bottom_sll = V_extrude_sll[findall(p -> isapprox(p[3], -h_sll; atol=1e-6), V_extrude_sll)] # find vertices at z=-h_sll
    V_bottom_sll = reorder_rectangular_boundary(V_bottom_sll, :xy) # reorder into rectangle
    R = ([1],)
    # Triangulate 
    F_bottom_sll, V_tri_bottom_sll = regiontrimesh((V_bottom_sll,), R, pointSpacing)

    # --- Join all geometry parts ---
    Fs, Vs, Cs = joingeom(
        F_bottom_faces, V_extrude_outer,
        F_extrude_sll, V_extrude_sll,
        F_bottom_sll, V_tri_bottom_sll
    )

    # --- Merge duplicate vertices ---
    Fs, Vs = mergevertices(Fs, Vs)

    # --- Define region and hole points ---
    V_regions = [Point{3,Float64}(l_pneunet / 2.0, 0.0, -h_sll / 2.0)]
    V_holes = [Point{3,Float64}(-1.0, 0.0, 0.0)]
    # --- TetGen options ---
    stringOpt = "pqAYQ"
    element_type = Tet10{Int}

    # --- Run TetGen meshing ---
    E_sll, V_sll, CE_sll, Fb_sll, Cb_sll = tetgenmesh(Fs, Vs;
        facetmarkerlist=Cs,
        V_regions=V_regions,
        V_holes=V_holes,
        stringOpt=stringOpt,
        element_type=element_type)

    return E_sll, V_sll, CE_sll, Fb_sll, Cb_sll
end
# ====================================================================

# ====================================================================
# 9 FEBio SIMULATION FUNCTIONS


"""
    FEBio_nodes_elements(saveDir, filename,
    V, V_sll,
    E, E_sll,
    Fb, F_sll,
    Cb,
    pointSpacing, n_chambers,
    l_first_chamber, l_chambers, l_gaps)

Prepares geometry for FEBio simulation
Nodes merged together. 
Element and face indices updated to reflect merge.
Internal facesa and contact faces defined
tri6 face orders updated to reflect FEBio order

# Returns
vectors of nodes, face indices and element indices
"""

function FEBio_nodes_elements(saveDir, filename,
    V, V_sll,
    E, E_sll,
    Fb, F_sll,
    Cb,
    pointSpacing, n_chambers,
    l_first_chamber, l_chambers, l_gaps)

    num_vert = length(V)

    # shift SLL vertices
    E_sll_shifted = [e .+ num_vert for e in E_sll]
    F_sll_shifted = [f .+ num_vert for f in F_sll]

    # merge V and V_sll
    nodes, indUnique, indMap = unique_vertices_hash(V, V_sll; tol=1e-4)

    # map ALL elements and faces to merged node indices
    elements_main = [Tet10{Int}(indMap[e]) for e in E]
    elements_sll = [Tet10{Int}(indMap[e]) for e in E_sll_shifted]

    Fb_mapped = [NgonFace{6,Int}(indMap[f]) for f in Fb]
    F_sll_mapped = [NgonFace{6,Int}(indMap[f]) for f in F_sll_shifted]

    # build Fb_all as 6-node faces (all mapped)
    Fb_all_6 = NgonFace{6,Int}.(Fb_mapped)
    append!(Fb_all_6, F_sll_mapped)
    Fb_all = Fb_all_6

    # paper shell faces (tri6) if present
    if paper == 1
        F_paper = find_faces_at_z(Fb_all, nodes, -h_sll; atol=1e-6)

        # flip normals for shell domain (tri6)
        F_paper = [NgonFace{6,Int}((f[1], f[3], f[5], f[2], f[4], f[6])) for f in F_paper]

        elements_paper = F_paper
        mesh_paper = GeometryBasics.Mesh(nodes, F_paper)
    else
        F_paper = nothing
        elements_paper = nothing
        mesh_paper = nothing
    end

    # internal faces (tri6, mapped)
    Fb_internal = Fb_mapped[(Cb.==2).|(Cb.==5).|(Cb.==6)]

    # fixed face on left – from Fb_all (tri6, mapped)
    Fb_fixed_face_left = find_faces_at_x(Fb_all, nodes, 0.0; atol=1e-6)

    # contact faces – from mapped Fb (tri6)
    Fb_extrude_outer = Fb_mapped[Cb.==1]
    Fb_faces_contact_primary = Vector{Vector{NgonFace{6,Int}}}(undef, n_chambers - 1)
    Fb_faces_contact_secondary = Vector{Vector{NgonFace{6,Int}}}(undef, n_chambers - 1)
    for j = 1:n_chambers-1
        x_distance_contact_face = l_first_chamber + (j - 1) * (l_gaps + l_chambers)

        Fb_faces_contact_primary[j] = find_faces_at_x(Fb_extrude_outer, nodes, x_distance_contact_face; atol=1e-6)
        Fb_faces_contact_secondary[j] = find_faces_at_x(Fb_extrude_outer, nodes, x_distance_contact_face + l_gaps; atol=1e-6)
    end

    # reorder tri6 faces for FEBio
    Fb_internal = [reorder_tri6_febio(Tuple(f), nodes) for f in Fb_internal]
    Fb_faces_contact_primary =
        [[reorder_tri6_febio(Tuple(f), nodes) for f in group]
         for group in Fb_faces_contact_primary]

    Fb_faces_contact_secondary =
        [[reorder_tri6_febio(Tuple(f), nodes) for f in group]
         for group in Fb_faces_contact_secondary]

    Fb_fixed_face_left =
        [reorder_tri6_febio(Tuple(f), nodes) for f in Fb_fixed_face_left]

    if paper == 1
        elements_paper = [reorder_tri6_febio(Tuple(f), nodes) for f in elements_paper]
    end

    return nodes,
    elements_main, elements_sll,
    elements_paper, F_paper, mesh_paper,
    Fb_all, Fb_internal, Fb_extrude_outer, Fb_fixed_face_left,
    Fb_faces_contact_primary, Fb_faces_contact_secondary # vectors of nodes, face indices and element indices
end

"""
    run_simulation(nodes, elements_main, elements_sll, elements_paper, Fb_internal, Fb_fixed_face_left, Fb_faces_contact_primary, Fb_faces_contact_secondary, pointSpacing, n_chambers, l_pneunet, h_full, h_sll, P, x, saveDir, filename)

Creates .feb file, submits this to FEBio, generates results for excel output. 

# Returns

"""

function run_simulation(nodes, elements_main, elements_sll, elements_paper, Fb_internal, Fb_fixed_face_left, Fb_faces_contact_primary, Fb_faces_contact_secondary, pointSpacing, n_chambers, l_pneunet, h_full, h_sll, P, x, saveDir, filename)

    # SIMULATION VARIABLES

    # Material Constants (Ogden)

    # # Dragon skin 10 (Ogden N1)
    # k_factor = 500 # Bulk modulus factor  
    # c1 = 0.258 # Shear-modulus-like parameter 
    # m1 = 2.6701 # Material parameter setting degree of non-linearity 
    # k = c1 * k_factor # Bulk modulus 

    # Dragon skin 10 (Ogden N1 new)
    k_factor = 500 # Bulk modulus factor  
    c1 = 0.07004*2.0 # Shear-modulus-like parameter 
    m1 = 2.7713 # Material parameter setting degree of non-linearity 
    k = c1 * k_factor # Bulk modulus 

    # # 3d print Elastico
    # c1 = 1.18
    # c2 = c1
    # m1 = 2
    # m2 = -m1
    # k = 58.47


    # # Dragon skin 10
    k_factor_sll = k_factor #Bulk modulus factor  
    c1_sll = c1 #Shear-modulus-like parameter [MPa]
    m1_sll = m1 #Material parameter setting degree of non-linearity 
    k_sll = c1_sll * k_factor_sll #Bulk modulus 

    # # XX60
    # c1_sll = 1.64
    # c2_sll = c1
    # m1_sll = 2
    # m2_sll = -m1
    # k_sll = 81.37


    # Paper
    youngs_paper = 2000 # [MPa]
    poisson_paper = 0.3
    shell_thickness = 0.05 # [mm]


    # Gravity parameters
    density = 1.07e-9 #tonne/mm^3 sourced from ecoflex/dragonskin manufacturer
    gravityConstant = 9.81 * 1e3 #mm/s^2
    gravityVector = Vec{3,Float64}(0.0, 0.0, gravityConstant)


    # Contact parameters
    contactPenalty = 10.0
    laugon = 1 # lagrangian augmentation
    minaug = 0
    maxaug = 15
    fric_coeff = 1.3
    initialSpacing = pointSpacing / 5.0


    ## FEA control settings
    numTimeSteps = 40 # for pressure steps
    numTimeSteps_grav = 10 # for gravity steps
    max_refs = 30 # Max reforms
    max_ups = 0 # Set to zero to use full-Newton iterations
    opt_iter = 15 # Optimum number of iterations # faster
    max_retries = 30 # Maximum number of retires
    dtmin = (1.0 / numTimeSteps) / 20.0 # Minimum time step size # faster
    dtmax = 1.0 / numTimeSteps # Maximum time step size
    symmetric_stiffness = 0 # turned off for sliding elastic contact
    min_residual = 1e-6


    # FILE NAMES
    if !isdir(saveDir)
        mkdir(saveDir)
    end
    filename_FEB = joinpath(saveDir, "$(filename).feb")   # The main FEBio input file
    filename_xplt = joinpath(saveDir, "$(filename).xplt") # The XPLT file for viewing results in FEBioStudio
    filename_log = joinpath(saveDir, "$(filename).txt") # The log file featuring the full FEBio terminal output stream
    filename_disp = "$(filename)_DISP.txt" # A log file for results saved in same directory as .feb file  e.g. nodal displacements
    filename_stress = "$(filename)_STRESS.txt" # A log file for results saved in same directory as .feb file  e.g. nodal stresses
    filename_excel_output = "$(filename)_output.xlsx" # Name of excel output file


    # .FEB FILE CREATION
    # Define febio input file XML
    doc, febio_spec_node = feb_doc_initialize()

    aen(febio_spec_node, "Module"; type="solid") # Define Module node: <Module type="solid"/>

    # # The following is only used for single timestep simulations
    # -----------------------------------------------------------------------
    # control_node = aen(febio_spec_node, "Control") # Define Control node: <Control>
        # aen(control_node, "analysis", "STATIC")
        # aen(control_node, "time_steps", numTimeSteps)
        # aen(control_node, "step_size", 1.0 / numTimeSteps)
        # aen(control_node, "plot_zero_state", 1)
        # aen(control_node, "plot_range", @sprintf("%.2f, %.2f", 0, -1))
        # aen(control_node, "plot_level", "PLOT_MAJOR_ITRS")
        # aen(control_node, "plot_stride", 1)
        # aen(control_node, "output_level", "OUTPUT_MAJOR_ITRS")
        # aen(control_node, "adaptor_re_solve", 1)

    # time_stepper_node = aen(control_node, "time_stepper"; type="default")
        # aen(time_stepper_node, "max_retries", max_retries)
        # aen(time_stepper_node, "opt_iter", opt_iter)
        # aen(time_stepper_node, "dtmin", dtmin)
        # if gravitySim == 1
        #     aen(time_stepper_node, "dtmax", dtmax; lc="2")
        # else
        #     aen(time_stepper_node, "dtmax", dtmax; lc="1")
        # end
        # aen(time_stepper_node, "dtmax", dtmax)
        # aen(time_stepper_node, "aggressiveness", 2) # faster
        # aen(time_stepper_node, "cutback", 5e-1) # faster
        # aen(time_stepper_node, "dtforce", 0)



    # solver_node = aen(control_node, "solver"; type="solid")
        # aen(solver_node, "symmetric_stiffness", symmetric_stiffness)
        # aen(solver_node, "equation_scheme", 1)
        # aen(solver_node, "equation_order", "default")
        # aen(solver_node, "optimize_bw", 1) # faster
        # aen(solver_node, "lstol", 5e-1)
        # aen(solver_node, "lsmin", 1e-2) # faster
        # aen(solver_node, "lsiter", 10) # faster
        # aen(solver_node, "max_refs", max_refs)
        # aen(solver_node, "check_zero_diagonal", 1)
        # aen(solver_node, "zero_diagonal_tol", 0)
        # aen(solver_node, "force_partition", 0)
        # aen(solver_node, "reform_each_time_step", 1) # relaxed 
        # aen(solver_node, "reform_augment", 0)
        # aen(solver_node, "diverge_reform", 1)
        # aen(solver_node, "min_residual", min_residual)
        # aen(solver_node, "max_residual", 0)
        # aen(solver_node, "dtol", 1e-3)
        # aen(solver_node, "etol", 1e-2)
        # aen(solver_node, "rtol", 0)
        # aen(solver_node, "rhoi", 0)
        # aen(solver_node, "alpha", 1)
        # aen(solver_node, "beta", 2.5e-01)
        # aen(solver_node, "gamma", 5e-01)
        # aen(solver_node, "logSolve", 0)
        # aen(solver_node, "arc_length", 0)
        # aen(solver_node, "arc_length_scale", 0)


    # qn_method_node = aen(solver_node, "qn_method"; type="BFGS")
        # aen(qn_method_node, "max_ups", max_ups)
        # aen(qn_method_node, "max_buffer_size", 0)
        # aen(qn_method_node, "cycle_buffer", 0)
        # aen(qn_method_node, "cmax", 0)
    # -----------------------------------------------------------------------

    # Globals
    Globals_node = aen(febio_spec_node, "Globals")

        Constants_node = aen(Globals_node, "Constants")
            aen(Constants_node, "R", 8.3140000e-06)
            aen(Constants_node, "T", 298)
            aen(Constants_node, "F", 9.6485000e-05)


    # Material properties
    Material_node = aen(febio_spec_node, "Material")

        material_node = aen(Material_node, "material"; id=1, name="main_Material", type="Ogden")
            aen(material_node, "c1", c1)
            aen(material_node, "m1", m1)
            aen(material_node, "k", k)
            aen(material_node, "density", density)

        material_node = aen(Material_node, "material"; id=2, name="sll_Material", type="Ogden")
            aen(material_node, "c1", c1_sll)
            aen(material_node, "m1", m1_sll)
            aen(material_node, "k", k_sll)
            aen(material_node, "density", density)

        material_node = aen(Material_node, "material"; id=3, name="paper_Material", type="neo-Hookean")
            aen(material_node, "E", youngs_paper)
            aen(material_node, "v", poisson_paper)
            aen(material_node, "density", density)


    # Mesh
    Mesh_node = aen(febio_spec_node, "Mesh")

        # Nodes
        Nodes_node = aen(Mesh_node, "Nodes"; name="nodeSet_all")
        for (i, v) in enumerate(nodes)
            aen(Nodes_node, "node", join([@sprintf("%.16e", x) for x ∈ v], ','); id=i)
        end

        # Elements
        Elements_node_main = aen(Mesh_node, "Elements"; name="elements_main", type="tet10")
        for (i, e) in enumerate(elements_main)
            aen(Elements_node_main, "elem",
                join([@sprintf("%i", n) for n ∈ e], ", ");
                id=i)
        end

        Elements_node_sll = aen(Mesh_node, "Elements"; name="elements_sll", type="tet10")
        for (i, e) in enumerate(elements_sll)
            aen(Elements_node_sll, "elem",
                join([@sprintf("%i", n) for n ∈ e], ", ");
                id=i)
        end

        if paper == 1
            Elements_node_paper = aen(Mesh_node, "Elements"; name="elements_paper", type="tri6")
            for (i, e) in enumerate(elements_paper)
                aen(Elements_node_paper, "elem",
                    join([@sprintf("%i", n) for n ∈ e], ", ");
                    id=i)
            end
        end


        # Node sets
        fixed_face_left = "fixed_face_left"
        fixed_nodes = unique(reduce(vcat, (collect(Tuple(f)) for f in Fb_fixed_face_left)))
        aen(Mesh_node, "NodeSet",
            join([@sprintf("%i", x) for x ∈ fixed_nodes], ',');
            name=fixed_face_left)


        # Surface sets
        internal = "internal"
        Surface_node = aen(Mesh_node, "Surface"; name="internal", elem_set="elements_main")
        for (i, e) in enumerate(Fb_internal)
            aen(Surface_node, "tri6", join([@sprintf("%i", j) for j ∈ e], ","); id=i)
        end

        for contact_face_no = 1:n_chambers-1
            surfaceName1 = @sprintf("Surface_%i", contact_face_no)
            Surface_node = aen(Mesh_node, "Surface"; name=surfaceName1, elem_set="elements_main")
            for (i, e) in enumerate(Fb_faces_contact_primary[contact_face_no])
                aen(Surface_node, "tri6", join([@sprintf("%i", j) for j in e], ','); id=i)
            end

            surfaceName2 = @sprintf("Surface_%i", contact_face_no + n_chambers - 1)
            Surface_node = aen(Mesh_node, "Surface"; name=surfaceName2, elem_set="elements_main")
            for (i, e) in enumerate(Fb_faces_contact_secondary[contact_face_no])
                aen(Surface_node, "tri6", join([@sprintf("%i", j) for j in e], ','); id=i)
            end

            surfacePairName = @sprintf("SurfacePair_%i", contact_face_no)
            SurfacePair_node = aen(Mesh_node, "SurfacePair"; name=surfacePairName)
                aen(SurfacePair_node, "primary", surfaceName1)
                aen(SurfacePair_node, "secondary", surfaceName2)
        end

    # Mesh Domains
    MeshDomains_node = aen(febio_spec_node, "MeshDomains")
        aen(MeshDomains_node, "SolidDomain"; mat="main_Material", name="elements_main")
        aen(MeshDomains_node, "SolidDomain"; mat="sll_Material", name="elements_sll")

    if paper == 1
        shell_node = aen(MeshDomains_node, "ShellDomain"; mat="paper_Material", name="elements_paper")
            aen(shell_node, "shell_thickness", shell_thickness)
    end

    # Boundary conditions
    Boundary_node = aen(febio_spec_node, "Boundary")

        bc_node = aen(Boundary_node, "bc"; name="zero_displacement_xyz", node_set=fixed_face_left, type="zero displacement")
            aen(bc_node, "x_dof", 1)
            aen(bc_node, "y_dof", 1)
            aen(bc_node, "z_dof", 1)

        for contact_face_no = 1:n_chambers-1
            surfacePairName = @sprintf("SurfacePair_%i", contact_face_no)
            Contact_node = aen(febio_spec_node, "Contact")
                contact_node = aen(Contact_node, "contact"; type="sliding-elastic", surface_pair=surfacePairName)
                    aen(contact_node, "two_pass", 0)
                    aen(contact_node, "laugon", laugon)
                    aen(contact_node, "tolerance", 0.2)
                    aen(contact_node, "gaptol", 0.05 * pointSpacing)
                    aen(contact_node, "minaug", minaug)
                    aen(contact_node, "maxaug", maxaug)
                    aen(contact_node, "search_tol", 0.01)
                    aen(contact_node, "search_radius", 2.0 * pointSpacing)
                    aen(contact_node, "symmetric_stiffness", symmetric_stiffness)
                    aen(contact_node, "auto_penalty", 1)
                    aen(contact_node, "penalty", contactPenalty)
                    aen(contact_node, "fric_coeff", fric_coeff)
        end

    # Loads
    Loads_node = aen(febio_spec_node, "Loads")

        surf_load_node = aen(Loads_node, "surface_load"; name="Pressure1", surface="internal", type="pressure")
        aen(surf_load_node, "pressure", @sprintf("%.16e", P); lc="1")
        aen(surf_load_node, "symmetric_stiffness", symmetric_stiffness)
        aen(surf_load_node, "linear", "0")
        aen(surf_load_node, "shell_bottom", "0")

        body_load_node = aen(Loads_node, "body_load"; type="const")
        aen(body_load_node, "x", gravityVector[1]; lc="2")
        aen(body_load_node, "y", gravityVector[2]; lc="2")
        aen(body_load_node, "z", gravityVector[3]; lc="2")

    # Load data
    LoadData_node = aen(febio_spec_node, "LoadData")

        load_controller_node = aen(LoadData_node, "load_controller"; id=1, name="LC_1", type="loadcurve")
        aen(load_controller_node, "interpolate", "LINEAR")

        points_node = aen(load_controller_node, "points")
            aen(points_node, "pt", @sprintf("%.2f, %.2f", 0.0, 0.0))
            aen(points_node, "pt", @sprintf("%.2f, %.2f", 1.0, 0.0))
            aen(points_node, "pt", @sprintf("%.2f, %.2f", 2.0, 1.0))

        if gravitySim == 1
            load_controller_node = aen(LoadData_node, "load_controller"; id=2, name="LC_2", type="loadcurve")
            aen(load_controller_node, "interpolate", "LINEAR")

            points_node = aen(load_controller_node, "points")
            aen(points_node, "pt", @sprintf("%.2f, %.2f", 0.0, 0.0))
            aen(points_node, "pt", @sprintf("%.2f, %.2f", 1.0, 1.0))
            aen(points_node, "pt", @sprintf("%.2f, %.2f", 2.0, 1.0))
        else
            load_controller_node = aen(LoadData_node, "load_controller"; id=2, name="LC_2", type="loadcurve")
            aen(load_controller_node, "interpolate", "LINEAR")

            points_node = aen(load_controller_node, "points")
            aen(points_node, "pt", @sprintf("%.2f, %.2f", 0.0, 0.0))
            aen(points_node, "pt", @sprintf("%.2f, %.2f", 1.0, 0.0))
            aen(points_node, "pt", @sprintf("%.2f, %.2f", 2.0, 0.0))
        end

    # Steps
    Step_node = aen(febio_spec_node, "Step")
        step1 = aen(Step_node, "step"; id="1")

            control_node = aen(step1, "Control") # Define Control node: <Control>
                aen(control_node, "analysis", "STATIC")
                aen(control_node, "time_steps", numTimeSteps_grav)
                aen(control_node, "step_size", 1.0 / numTimeSteps_grav)
                aen(control_node, "plot_zero_state", 1)
                aen(control_node, "plot_range", @sprintf("%.2f, %.2f", 0, -1))
                aen(control_node, "plot_level", "PLOT_MAJOR_ITRS")
                aen(control_node, "plot_stride", 1)
                aen(control_node, "output_level", "OUTPUT_MAJOR_ITRS")
                aen(control_node, "adaptor_re_solve", 1)



                time_stepper_node = aen(control_node, "time_stepper"; type="default")
                    aen(time_stepper_node, "max_retries", max_retries)
                    aen(time_stepper_node, "opt_iter", opt_iter)
                    aen(time_stepper_node, "dtmin", 0.1)
                    aen(time_stepper_node, "dtmax", 0.2)
                    aen(time_stepper_node, "aggressiveness", 0) # faster
                    aen(time_stepper_node, "cutback", 5e-1) # faster
                    aen(time_stepper_node, "dtforce", 0)

                solver_node = aen(control_node, "solver"; type="solid")
                    aen(solver_node, "symmetric_stiffness", symmetric_stiffness)
                    aen(solver_node, "equation_scheme", 1)
                    aen(solver_node, "equation_order", "default")
                    aen(solver_node, "optimize_bw", 1) # faster
                    aen(solver_node, "lstol", 5e-1)
                    aen(solver_node, "lsmin", 1e-2) # faster
                    aen(solver_node, "lsiter", 10) # faster
                    aen(solver_node, "max_refs", max_refs)
                    aen(solver_node, "check_zero_diagonal", 1)
                    aen(solver_node, "zero_diagonal_tol", 0)
                    aen(solver_node, "force_partition", 0)
                    aen(solver_node, "reform_each_time_step", 1) # relaxed 
                    aen(solver_node, "reform_augment", 0)
                    aen(solver_node, "diverge_reform", 1)
                    aen(solver_node, "min_residual", min_residual)
                    aen(solver_node, "max_residual", 0)
                    aen(solver_node, "dtol", 1e-3)
                    aen(solver_node, "etol", 1e-2)
                    aen(solver_node, "rtol", 0)
                    aen(solver_node, "rhoi", 0)
                    aen(solver_node, "alpha", 1)
                    aen(solver_node, "beta", 2.5e-01)
                    aen(solver_node, "gamma", 5e-01)
                    aen(solver_node, "logSolve", 0)
                    aen(solver_node, "arc_length", 0)
                    aen(solver_node, "arc_length_scale", 0)


                qn_method_node = aen(solver_node, "qn_method"; type="BFGS")
                    aen(qn_method_node, "max_ups", max_ups)
                    aen(qn_method_node, "max_buffer_size", 0)
                    aen(qn_method_node, "cycle_buffer", 0)
                    aen(qn_method_node, "cmax", 0)


        step2 = aen(Step_node, "step"; id="2")
            control_node = aen(step2, "Control") # Define Control node: <Control>
                aen(control_node, "analysis", "STATIC")
                aen(control_node, "time_steps", numTimeSteps)
                aen(control_node, "step_size", 1.0 / numTimeSteps)
                aen(control_node, "plot_zero_state", 1)
                aen(control_node, "plot_range", @sprintf("%.2f, %.2f", 0, -1))
                aen(control_node, "plot_level", "PLOT_MAJOR_ITRS")
                aen(control_node, "plot_stride", 1)
                aen(control_node, "output_level", "OUTPUT_MAJOR_ITRS")
                aen(control_node, "adaptor_re_solve", 1)


                time_stepper_node = aen(control_node, "time_stepper"; type="default")
                    aen(time_stepper_node, "max_retries", max_retries)
                    aen(time_stepper_node, "opt_iter", opt_iter)
                    aen(time_stepper_node, "dtmin", dtmin)
                    aen(time_stepper_node, "dtmax", dtmax)
                    aen(time_stepper_node, "aggressiveness", 0) # faster
                    aen(time_stepper_node, "cutback", 5e-1) # faster
                    aen(time_stepper_node, "dtforce", 0)

                solver_node = aen(control_node, "solver"; type="solid")
                    aen(solver_node, "symmetric_stiffness", symmetric_stiffness)
                    aen(solver_node, "equation_scheme", 1)
                    aen(solver_node, "equation_order", "default")
                    aen(solver_node, "optimize_bw", 1) # faster
                    aen(solver_node, "lstol", 5e-1)
                    aen(solver_node, "lsmin", 1e-2) # faster
                    aen(solver_node, "lsiter", 10) # faster
                    aen(solver_node, "max_refs", max_refs)
                    aen(solver_node, "check_zero_diagonal", 1)
                    aen(solver_node, "zero_diagonal_tol", 0)
                    aen(solver_node, "force_partition", 0)
                    aen(solver_node, "reform_each_time_step", 1) # relaxed 
                    aen(solver_node, "reform_augment", 0)
                    aen(solver_node, "diverge_reform", 1)
                    aen(solver_node, "min_residual", min_residual)
                    aen(solver_node, "max_residual", 0)
                    aen(solver_node, "dtol", 1e-3)
                    aen(solver_node, "etol", 1e-2)
                    aen(solver_node, "rtol", 0)
                    aen(solver_node, "rhoi", 0)
                    aen(solver_node, "alpha", 1)
                    aen(solver_node, "beta", 2.5e-01)
                    aen(solver_node, "gamma", 5e-01)
                    aen(solver_node, "logSolve", 0)
                    aen(solver_node, "arc_length", 0)
                    aen(solver_node, "arc_length_scale", 0)

                qn_method_node = aen(solver_node, "qn_method"; type="BFGS")
                    aen(qn_method_node, "max_ups", max_ups)
                    aen(qn_method_node, "max_buffer_size", 0)
                    aen(qn_method_node, "cycle_buffer", 0)
                    aen(qn_method_node, "cmax", 0)

    # Output
    Output_node = aen(febio_spec_node, "Output")

        plotfile_node = aen(Output_node, "plotfile"; type="febio")
            aen(plotfile_node, "var"; type="displacement")
            aen(plotfile_node, "var"; type="stress")
            aen(plotfile_node, "var"; type="relative volume")
            aen(plotfile_node, "var"; type="reaction forces")
            aen(plotfile_node, "var"; type="contact pressure")
            aen(plotfile_node, "compression", @sprintf("%i", 0))

        logfile_node = aen(Output_node, "logfile"; file=filename_log)
            aen(logfile_node, "node_data"; data="ux;uy;uz", delim=",", file=filename_disp)
            aen(logfile_node, "element_data"; data="s1;s2;s3", delim=",", file=filename_stress)

    # Write FEB file
    XML.write(filename_FEB, doc)


    # RUN FEBIO
    if runFEBio == 1
        run_febio(filename_FEB, FEBIO_EXEC)

        if outputExcel == 1
            # Find tip displacement 
            end_ind = findall(v -> isapprox(v[1], l_pneunet; atol=1e-6), nodes) # find node at far right of pneunet at y=l_pneunet
            top_tip_ind = filter(i -> isapprox(nodes[i][3], h_full; atol=1e-6), end_ind) # find node at top right of pneunet at z=h_full
            bottom_tip_ind = filter(i -> isapprox(nodes[i][3], -h_sll; atol=1e-6), end_ind) # find node at bottom right of pneunet at z=h_sll


            # Import results
            DD_disp = read_logfile(joinpath(saveDir, filename_disp)) # read displacements from log file
            numInc = length(DD_disp) # find length of log file (number of time steps)
            times = [DD_disp[k].time for k in sort(collect(keys(DD_disp)))] # read times

            # Create time varying vectors
            UT = [copy(nodes) for _ in 1:numInc] # displacement
            VT = [copy(nodes) for _ in 1:numInc] # co-ordinate
            @inbounds for i in 0:1:numInc-1
                UT[i+1] = [Point{3,Float64}(u) for u in DD_disp[i].data]
                VT[i+1] += UT[i+1]
            end

            # Preallocate
            top_tip_mean_disp_xz = Vector{Tuple{Float64,Float64}}(undef, numInc) # top end edge mean displacements
            bottom_tip_mean_disp_xz = Vector{Tuple{Float64,Float64}}(undef, numInc) # bottom end edge mean displacements
            top_tip_mean_coord_xz = Vector{Tuple{Float64,Float64}}(undef, numInc) # top end edge mean coordinates
            bottom_tip_mean_coord_xz = Vector{Tuple{Float64,Float64}}(undef, numInc) # bottom end edge mean coordinates
            θ_deg = Vector{Float64}(undef, numInc) # angle between end face and yz (vertical) plane 

            for j = 1:numInc # loop over all timesteps
                # mean displacements
                top_tip_mean_disp_xz[j] = (mean([UT[j][i][1] for i in top_tip_ind]),
                    mean([UT[j][i][3] for i in top_tip_ind]))

                bottom_tip_mean_disp_xz[j] = (mean([UT[j][i][1] for i in bottom_tip_ind]),
                    mean([UT[j][i][3] for i in bottom_tip_ind]))

                # mean coordinates
                top_tip_mean_coord_xz[j] = (mean([VT[j][i][1] for i in top_tip_ind]),
                    mean([VT[j][i][3] for i in top_tip_ind]))

                bottom_tip_mean_coord_xz[j] = (mean([VT[j][i][1] for i in bottom_tip_ind]),
                    mean([VT[j][i][3] for i in bottom_tip_ind]))

                # differences between top and bottom coordinates
                dx = top_tip_mean_coord_xz[j][1] - bottom_tip_mean_coord_xz[j][1]
                dz = top_tip_mean_coord_xz[j][2] - bottom_tip_mean_coord_xz[j][2]

                # angle of end face
                θ = π / 2 - atan(dz, dx)
                θ_deg[j] = θ * 180 / π
            end

            # EXPORT TIP DISPLACEMENTS TO EXCEL
            export_vectors_to_excel(joinpath(saveDir, filename_excel_output),
                θ_deg,
                top_tip_mean_coord_xz,
                bottom_tip_mean_coord_xz,
                top_tip_mean_disp_xz,
                bottom_tip_mean_disp_xz,
                times,
                P)
        end
    end

    return nothing
end



"""
    build_geometry_for_visualization(pointSpacing, n_chambers,
    h_full, h_base, h_ceiling_channel, h_floor_gap, h_ceiling_chamber,
    l_first_chamber, l_first_wall, l_gaps, l_chambers, l_walls,
    l_end_wall, l_end_chamber,
    d_full, d_side)

Generates pneunet geometry for visualisation (using sliders).
Similar to how geometry created for simulation, less tetgenmesh.

# Returns
Faces and corresponding vertices of pneunet geometry
"""

function build_geometry_for_visualization(pointSpacing, n_chambers,
    h_full, h_base, h_ceiling_channel, h_floor_gap, h_ceiling_chamber,
    l_first_chamber, l_first_wall, l_gaps, l_chambers, l_walls,
    l_end_wall, l_end_chamber,
    d_full, d_side)

    params = (; pointSpacing, n_chambers,
        h_full, h_base, h_ceiling_channel, h_floor_gap, h_ceiling_chamber,
        l_first_chamber, l_first_wall, l_gaps, l_chambers, l_walls,
        l_end_wall, l_end_chamber,
        d_full, d_side)

    V_boundary_inner, V_boundary_outer, l_pneunet = build_boundaries(pointSpacing, n_chambers,
        h_full, h_base, h_ceiling_channel, h_floor_gap, h_ceiling_chamber,
        l_first_chamber, l_first_wall, l_gaps, l_chambers, l_walls,
        l_end_wall, l_end_chamber,
        d_full, d_side)

    # CREATE EXTRUDED FACES
    F_extrude_inner, V_extrude_inner, F_extrude_outer, V_extrude_outer = extrude_boundaries(V_boundary_inner, V_boundary_outer, d_full, d_side, pointSpacing)

    # CREATE END FACES
    F_back_outer, V_back_outer, F_front_outer, V_front_outer, F_back_inner, V_back_inner, F_front_inner, V_front_inner = build_endcaps(V_boundary_inner, V_boundary_outer, d_full, d_side, pointSpacing, h_floor_gap, h_ceiling_channel)

    return F_extrude_inner, V_extrude_inner, F_extrude_outer, V_extrude_outer, F_back_outer, V_back_outer, F_back_inner, V_front_outer, F_front_inner, V_back_inner, F_front_outer, V_front_inner
end
# ====================================================================

# ====================================================================
# 10 STL CREATION FUNCTIONS
"""
    build_connector(pointSpacing_stl, r_hole1, r_shaft3, r_bite4, r_point5, h_connector_inset, h_connector2, h_shaft3, h_bite4, h_loft5, h_full, d_full, h_ceiling_chamber, d_side, h_base)

Creates connector geometry for stl. 
Builds from bottom up, starting with portion that inserts into pneunet, ending with top of air connection

# Returns
Face and vertex vectors
"""

function build_connector(pointSpacing_stl, r_hole1, r_shaft3, r_bite4, r_point5, h_connector_inset, h_connector2, h_shaft3, h_bite4, h_loft5, h_full, d_full, h_ceiling_chamber, d_side, h_base)
    # Regiontrimesh and extrudecurve settings
    R = ([1, 2],)
    P = (pointSpacing_stl,)
    n = Vec3{Float64}(0.0, 0.0, 1.0)
    direction = :positive

    # Insert into pneunet, bottom face
    half_width_inside = (d_full - 2 * d_side) / 2.0
    half_height_inside = (h_ceiling_chamber - h_base) / 2.0
    V_1_inset_corners = [
        Point{3,Float64}(-half_width_inside, -half_height_inside, 0.0), # bottom right corner
        Point{3,Float64}(-half_width_inside, half_height_inside, 0.0), # top right corner
        Point{3,Float64}(half_width_inside, half_height_inside, 0.0), # top left corner
        Point{3,Float64}(half_width_inside, -half_height_inside, 0.0) # bottom left corner
    ]
    mustpoints_inset = collect(1:length(V_1_inset_corners))
    V_1_inset = evenly_space(V_1_inset_corners, pointSpacing_stl, close_loop=true, spline_order=2,
        must_points=mustpoints_inset) # Interpolate between corners

    V_1_hole = circlepoints(r_hole1, max(5, ceil(Int, 2 * 3 * r_hole1 / pointSpacing_stl)); dir=:acw) # hole at centre

    VT_1 = (reverse(V_1_inset), V_1_hole) # make vector suitable for regiontrimesh
    F_1_rectangle_base, V_1_rectangle_base = regiontrimesh(VT_1, R, P) # bottom surface

    # Insert into pneunet, extrusion upwards
    F_1, V_1 = extrudecurve(
        V_1_inset;
        extent=h_connector_inset,
        direction=direction,
        n=n,
        num_steps=floor(Int, h_connector_inset / pointSpacing_stl) + 1,
        close_loop=true,
        face_type=:forwardslash
    )

    # Flange out to full with and height of pneunet, same as done for bottom surface
    right_left = d_full / 2.0
    up = half_height_inside + (h_full - h_ceiling_chamber)
    down = half_height_inside + h_sll + h_base
    V_2_outside_corners = [
        Point{3,Float64}(-right_left, -down, h_connector_inset), # bottom right corner
        Point{3,Float64}(-right_left, up, h_connector_inset), # top right corner
        Point{3,Float64}(right_left, up, h_connector_inset), # top left corner
        Point{3,Float64}(right_left, -down, h_connector_inset) # bottom left corner
    ]
    mustpoints_inset = collect(1:length(V_2_outside_corners))
    V_2_outside = evenly_space(V_2_outside_corners, pointSpacing_stl, close_loop=true, spline_order=2,
        must_points=mustpoints_inset)
    V_2_inset = [Point{3,Float64}(p[1], p[2], h_connector_inset) for p in V_1_inset] # top points of previous extrusion to give inside points for regiontrimesh
    VT_2 = (reverse(V_2_outside), reverse(V_2_inset))
    F_2_outer, V_2_outer = regiontrimesh(VT_2, R, P)

    # Extrude upwards
    F_2, V_2 = extrudecurve(
        V_2_outside;
        extent=h_connector2,
        direction=direction,
        n=n,
        num_steps=floor(Int, h_connector2 / pointSpacing_stl) + 2,
        close_loop=true,
        face_type=:forwardslash
    )

    ## Top surface
    V_3_outside = [Point{3,Float64}(p[1], p[2], h_connector_inset + h_connector2) for p in V_2_outside] # top points of previous extrusion to give outside points for regiontrimesh
    V_3_shaft = circlepoints(r_shaft3, ceil(Int, 2 * 3 * r_shaft3 / pointSpacing_stl); dir=:acw) # outer points for shaft
    V_3_shaft = [Point{3,Float64}(p[1], p[2], h_connector_inset + h_connector2) for p in V_3_shaft] # translate to correct z-coordinates, inside of regiontrimesh
    VT_3 = (reverse(V_3_outside), V_3_shaft)
    F_3_flat, V_3_flat = regiontrimesh(VT_3, R, P)

    # Extrude shaft upwards
    F_3, V_3 = extrudecurve(
        V_3_shaft;
        extent=h_shaft3,
        direction=direction,
        n=n,
        num_steps=floor(Int, h_connector2 / pointSpacing_stl) + 2,
        close_loop=true,
        face_type=:forwardslash
    )

    # Bite to hold pneumatic tube
    V_4_bite = circlepoints(r_bite4, ceil(Int, 2 * 3 * r_bite4 / pointSpacing_stl); dir=:acw) # outer points of bits
    V_4_bite = [Point{3,Float64}(p[1], p[2], h_connector_inset + h_connector2 + h_shaft3) for p in V_4_bite] # translate to correct z-coordinates, outside of regiontrimesh
    V_4_shaft = [Point{3,Float64}(p[1], p[2], h_connector_inset + h_connector2 + h_shaft3) for p in V_3_shaft] # translate to correct z-coordinates, inside of regiontrimesh 
    VT_4 = (V_4_bite, V_4_shaft)
    F_4_flat, V_4_flat = regiontrimesh(VT_4, R, P)

    # Extrude bite upwards
    F_4, V_4 = extrudecurve(
        V_4_bite;
        extent=h_bite4,
        direction=direction,
        n=n,
        num_steps=floor(Int, h_bite4 / pointSpacing_stl) + 2,
        close_loop=true,
        face_type=:forwardslash
    )

    # Loft bite upwards
    V_5_bite = [Point{3,Float64}(p[1], p[2], h_connector_inset + h_connector2 + h_shaft3 + h_bite4) for p in V_4_bite] # translate to correct z-coordinates, bottom of loft
    V_5_point = circlepoints(r_point5, length(V_5_bite); dir=:acw) # outer points of top surface
    V_5_point = [Point{3,Float64}(p[1], p[2], h_connector_inset + h_connector2 + h_shaft3 + h_bite4 + h_loft5) for p in V_5_point] # translate to correct z-coordinates, top of regiontrimesh, outside of regiontrimesh
    F_5, V_5 = loftlinear(V_5_bite, V_5_point; num_steps=floor(Int, h_loft5 / pointSpacing_stl) + 2, close_loop=true, face_type=:forwardslash) # loft bite

    # Cap with top surface
    V_5_hole = [Point{3,Float64}(p[1], p[2], h_connector_inset + h_connector2 + h_shaft3 + h_bite4 + h_loft5) for p in V_1_hole]
    VT_5 = (V_5_point, V_5_hole)
    F_5_flat, V_5_flat = regiontrimesh(VT_5, R, P)

    # Inner hole extrusion
    F_5_hole, V_5_hole = extrudecurve(
        V_1_hole;
        extent=h_connector_inset + h_connector2 + h_shaft3 + h_bite4 + h_loft5,
        direction=direction,
        n=n,
        num_steps=floor(Int, (h_connector_inset + h_connector2 + h_shaft3 + h_bite4 + h_loft5) / pointSpacing_stl) + 2,
        close_loop=true,
        face_type=:forwardslash
    )

    # --- Join all geometry parts ---
    Fs_connector, Vs_connector, _ = joingeom(F_1_rectangle_base, V_1_rectangle_base,
        F_1, V_1,
        F_2_outer, V_2_outer,
        F_2, V_2,
        F_3_flat, V_3_flat,
        F_3, V_3,
        F_4_flat, V_4_flat,
        F_4, V_4,
        F_5, V_5,
        F_5_flat, V_5_flat,
        F_5_hole, V_5_hole)

    # --- Merge duplicate vertices ---
    Fs_connector, Vs_connector = mergevertices(Fs_connector, Vs_connector)
    
    return Fs_connector, Vs_connector # Face and vertex vectors
end

"""
    extrude_boundaries_stl(V_boundary_inner, V_boundary_outer, h_full, h_ceiling_chamber, h_base, d_full, d_side, pointSpacing_stl)

Creates geometry of extrusion portions of pneunet for 3D printing, without end face where connector inserts, this window will be created in pneunet_connector_end_stl()

# Returns
Faces and vertex vectors
"""

function extrude_boundaries_stl(V_boundary_inner, V_boundary_outer, h_full, h_ceiling_chamber, h_base, d_full, d_side, pointSpacing_stl)

    # Edit V_boundary_outer and V_boundary inner to exclude connector side edge
    deleteat!(V_boundary_outer, 2:ceil(Int, h_full / pointSpacing_stl))
    circshift!(V_boundary_outer, -1)
    deleteat!(V_boundary_inner, 2:ceil(Int, (h_ceiling_chamber - h_base) / pointSpacing_stl))
    circshift!(V_boundary_inner, -1)

    # Extrusion vector in Y-direction
    n = Vec3{Float64}(0.0, 1.0, 0.0)

    # --- Outer extrusion ---
    num_steps_width = 1 + ceil(Int, d_full / pointSpacing_stl)
    F_extrude_outer, V_extrude_outer = extrudecurve(
        V_boundary_outer;
        extent=d_full,
        direction=:both,
        n=n,
        num_steps=num_steps_width,
        close_loop=false,
        face_type=:forwardslash
    )

    # --- Inner extrusion ---
    num_steps_width_inner = 1 + ceil(Int, (d_full - d_side) / pointSpacing_stl)
    F_extrude_inner, V_extrude_inner = extrudecurve(
        V_boundary_inner;
        extent=d_full - 2.0 * d_side,
        direction=:both,
        n=n,
        num_steps=num_steps_width_inner,
        close_loop=false,
        face_type=:forwardslash
    )

    # Flip inner faces so normals point outward
    F_extrude_inner = [reverse(f) for f in F_extrude_inner]

    return F_extrude_inner, V_extrude_inner, F_extrude_outer, V_extrude_outer # Face and vertex vectors
end

"""
    pneunet_connector_end_stl(F_joingeom_inner_stl, V_joingeom_inner_stl, pointSpacing_stl, h_full, h_ceiling_chamber, h_base, h_sll, h_connector_inset, d_full, d_side, l_first_wall)

Creates window in one end of pneunet to allow insertion of connector, only for 3D printed pneunet
Creates surfaces from inside of pneunet to outside of pneunet first using extrudecurve. 
Then creates outer end face using regiontrimesh

# Returns
Faces and vertex vectors
"""

function pneunet_connector_end_stl(F_joingeom_inner_stl, V_joingeom_inner_stl, pointSpacing_stl, h_full, h_ceiling_chamber, h_base, h_sll, h_connector_inset, d_full, d_side, l_first_wall)
    # Regiontrimesh and extrudecurve settings
    R = ([1, 2],)
    P = (pointSpacing_stl,)
    n = Vec3{Float64}(1.0, 0.0, 0.0)
    direction = :negative

    # Find indices of points whose x-coordinate (first component) is approximately `l_first_wall`
    V_1_inset_ind = findall(p -> isapprox(p[1], l_first_wall; atol=1e-6), V_joingeom_inner_stl)
    V_1_inset = V_joingeom_inner_stl[V_1_inset_ind]
    V_1_inset = reorder_rectangular_boundary(V_1_inset, :yz)

    # extrude inset boundary from inner surface to outer face
    F_1, V_1 = extrudecurve(
        V_1_inset;
        extent=l_first_wall,
        direction=direction,
        n=n,
        num_steps=floor(Int, l_first_wall / pointSpacing_stl) + 2,
        close_loop=true,
        face_type=:forwardslash
    )

    # create outer end face
    V_2_outside_corners = [
        Point{3,Float64}(0.0, -d_full / 2, 0.0), # bottom right corner
        Point{3,Float64}(0.0, -d_full / 2, h_full), # top right corner
        Point{3,Float64}(0.0, d_full / 2, h_full), # top left corner
        Point{3,Float64}(0.0, d_full / 2, 0.0) # bottom left corner
    ]
    mustpoints_inset = collect(1:length(V_2_outside_corners))
    V_2_outside = evenly_space(V_2_outside_corners, pointSpacing_stl, close_loop=true, spline_order=2,
        must_points=mustpoints_inset)
    V_2_outside = [Point{3,Float64}(p[3], p[2], 0.0) for p in V_2_outside] # rotate boundary for regiontrimesh
    V_2_inset = [Point{3,Float64}(p[3], p[2], 0.0) for p in V_1_inset] # create outside boundary from inside boundary and rotate for regiontrimesh


    VT_2 = (
        V_2_outside, V_2_inset)
    F_2_outer, V_2_outer = regiontrimesh(VT_2, R, P)
    V_2_outer = [Point{3,Float64}(0.0, p[2], p[1]) for p in V_2_outer] # rotate back to orginial orrientation

    # join extrudecurve and regiontrimesh surfaces
    F_pneunet_connector_end_set, V_pneunet_connector_end_set = joingeom(F_1, V_1, F_2_outer, V_2_outer)

    return F_pneunet_connector_end_set, V_pneunet_connector_end_set # Face and vertex vectors
end

"""
    build_sll_for_stl(F_extrude_outer, V_extrude_outer, h_sll, d_full, l_pneunet, pointSpacing)

Creates geometry of strain limiting layer for stl output. 
Copies faces at bottom of pneunet main body. 
Creates new boundary curve and extrudes downwards. 
Regiontrimesh closes off bottom. 

# Returns
Faces and vertex vectors
"""
function build_sll_for_stl(F_extrude_outer, V_extrude_outer, h_sll, d_full, l_pneunet, pointSpacing_stl)
    # Identify bottom faces (z ≈ 0.0) 
    F_bottom_faces = find_faces_at_z(F_extrude_outer, V_extrude_outer, 0.0; atol=1e-6)

    # Outline of strain limiting layer boundary at z=0.0
    V_bottom_outline_corners = [
        Point{3,Float64}(0.0, d_full / 2.0, 0.0),
        Point{3,Float64}(0.0, -d_full / 2.0, 0.0),
        Point{3,Float64}(l_pneunet, -d_full / 2.0, 0.0),
        Point{3,Float64}(l_pneunet, d_full / 2.0, 0.0),
    ]

    # Interpolate boundary
    must_points = collect(1:length(V_bottom_outline_corners))
    V_bottom_outline = evenly_space(V_bottom_outline_corners, pointSpacing_stl;
        close_loop=true, spline_order=2,
        must_points=must_points)

    n = Vec3{Float64}(0.0, 0.0, 1.0)

    # --- Outer extrusion ---
    num_steps_width = max(3, ceil(Int, h_sll / pointSpacing_stl)) # minimum of 3
    F_extrude_sll, V_extrude_sll = extrudecurve(
        V_bottom_outline;
        extent=h_sll,
        direction=:negative,
        n=n,
        num_steps=num_steps_width,
        close_loop=true,
        face_type=:forwardslash
    )

    # bottom sll
    V_bottom_sll = V_extrude_sll[findall(p -> isapprox(p[3], -h_sll; atol=1e-6), V_extrude_sll)] # find vertices at z=-h_sll
    V_bottom_sll = reorder_rectangular_boundary(V_bottom_sll, :xy) # reorder into rectangle
    R = ([1],)
    # Triangulate 
    F_bottom_sll, V_tri_bottom_sll = regiontrimesh((V_bottom_sll,), R, pointSpacing_stl)

    # --- Join all geometry parts ---
    Fs, Vs, Cs = joingeom(
        F_bottom_faces, V_extrude_outer,
        F_extrude_sll, V_extrude_sll,
        F_bottom_sll, V_tri_bottom_sll
    )

    # --- Merge duplicate vertices ---
    Fs, Vs = mergevertices(Fs, Vs)

    return Fs, Vs
end

"""
    build_pneunet_for_stl(pointSpacing_stl, n_chambers,
    h_full, h_base, h_ceiling_channel, h_floor_gap, h_ceiling_chamber,
    l_first_chamber, l_first_wall, l_gaps, l_chambers, l_walls,
    l_end_wall, l_end_chamber,
    d_full, d_side)

Creates geometry of 3D printed pneunet. 
Similar process to creating pneunet for simulation but includes window in geometry to allow insertion of connector. 
Does not tetgenmesh

# Returns
Faces and vertex vectors
"""

function build_pneunet_for_stl(pointSpacing_stl, n_chambers,
    h_full, h_base, h_ceiling_channel, h_floor_gap, h_ceiling_chamber,
    l_first_chamber, l_first_wall, l_gaps, l_chambers, l_walls,
    l_end_wall, l_end_chamber,
    d_full, d_side)
    # Use existing made geometry, 
    V_boundary_inner, V_boundary_outer, l_pneunet = build_boundaries(pointSpacing_stl, n_chambers,
        h_full, h_base, h_ceiling_channel, h_floor_gap, h_ceiling_chamber,
        l_first_chamber, l_first_wall, l_gaps, l_chambers, l_walls,
        l_end_wall, l_end_chamber,
        d_full, d_side)

    # #use endcaps as is, 
    F_back_outer, V_back_outer, F_front_outer, V_front_outer, F_back_inner, V_back_inner, F_front_inner, V_front_inner = build_endcaps(V_boundary_inner, V_boundary_outer, d_full, d_side, pointSpacing_stl, h_floor_gap, h_ceiling_channel)
    # #create all geometry as normal 
    F_extrude_inner, V_extrude_inner, F_extrude_outer, V_extrude_outer = extrude_boundaries_stl(V_boundary_inner, V_boundary_outer, h_full, h_ceiling_chamber, h_base, d_full, d_side, pointSpacing_stl)
    F_joingeom_inner_stl, V_joingeom_inner_stl = joingeom(F_back_inner, V_back_inner, F_front_inner, V_front_inner, F_extrude_inner, V_extrude_inner)
    # except pneunet end bit
    F_pneunet_connector_end_set, V_pneunet_connector_end_set = pneunet_connector_end_stl(F_joingeom_inner_stl, V_joingeom_inner_stl, pointSpacing_stl, h_full, h_ceiling_chamber, h_base, h_sll, h_connector_inset, d_full, d_side, l_first_wall)

    # # TETGENMESH
    # # --- Join all geometry parts ---
    Fs_pneunet, Vs_pneunet, Cs_pneunet = joingeom(F_back_outer, V_back_outer, F_front_outer, V_front_outer, F_back_inner, V_back_inner, F_front_inner, V_front_inner, F_extrude_inner, V_extrude_inner, F_extrude_outer, V_extrude_outer, F_pneunet_connector_end_set, V_pneunet_connector_end_set)

    # # --- Merge duplicate vertices ---
    Fs_pneunet, Vs_pneunet = mergevertices(Fs_pneunet, Vs_pneunet)

    Fb_sll_stl, V_sll = build_sll_for_stl(F_extrude_outer, V_extrude_outer, h_sll, d_full, l_pneunet, pointSpacing_stl)


    return Fs_pneunet, Vs_pneunet, Fb_sll_stl, V_sll # Faces and vertex vectors
end

"""
    build_boundaries_for_stl(
    pointSpacing_stl,   
    n_chambers,     
    h_full,      
    h_base,         
    h_ceiling_channel, 
    h_floor_gap,       
    h_ceiling_chamber,
    l_first_chamber,   
    l_first_wall,    
    l_gaps,         
    l_chambers,      
    l_walls,      
    l_end_wall,     
    l_end_chamber,  
    d_full,   
    d_side    
    )

Creates inner boundaries of pneunet which are regiontrimeshed for 3D printed pneunet. 
Similar to build_boundaries() but does not create inner boundaries

# Returns

"""

function build_boundaries_for_stl(
    pointSpacing_stl,        # Float64 → spacing between interpolated mesh points
    n_chambers,          # Int → number of chambers including start and end

    ## x-direction (heights)
    h_full,              # Float64 → full height of the pneunet
    h_base,              # Float64 → thickness of the strain-limiting base layer
    h_ceiling_channel,   # Float64 → z-height of the channel ceiling
    h_floor_gap,         # Float64 → z-height of the channel floor gap
    h_ceiling_chamber,   # Float64 → z-height of the chamber ceiling

    ## z-direction (lengths along extrusion)
    l_first_chamber,     # Float64 → length of the very first chamber
    l_first_wall,        # Float64 → thickness of the first wall
    l_gaps,              # Float64 → length of the channel gap between chambers
    l_chambers,          # Float64 → length of each repeated chamber
    l_walls,             # Float64 → thickness of each repeated wall
    l_end_wall,          # Float64 → thickness of the final wall
    l_end_chamber,       # Float64 → length of the last chamber

    ## y-direction (depths)
    d_full,              # Float64 → total depth of the pneunet (y-direction)
    d_side               # Float64 → side wall depth (y-direction offset)
)

    l_pneunet = l_first_chamber + l_gaps * (n_chambers - 1) + l_chambers * (n_chambers - 2) + l_end_chamber



    # --- First chamber inner ---
    V_first_chamber_inner = [
        Point{3,Float64}(0.0, 0.0, h_base),
        Point{3,Float64}(0.0, 0.0, h_ceiling_chamber),
        Point{3,Float64}(l_first_chamber - l_walls, 0.0, h_ceiling_chamber),
        Point{3,Float64}(l_first_chamber - l_walls, 0.0, h_ceiling_channel),
        Point{3,Float64}(l_first_chamber + l_gaps + l_walls, 0.0, h_ceiling_channel),
    ]
    V_corners_inner = copy(V_first_chamber_inner)

    # --- Repeated chambers ---
    for i ∈ 1:(n_chambers-2)
        offset_inner = l_first_chamber + l_gaps + (Float64(i - 1) * (l_chambers + l_gaps)) + l_walls
        V_repeated_chambers_inner = [
            Point{3,Float64}(offset_inner, 0.0, h_ceiling_chamber),
            Point{3,Float64}(offset_inner + l_chambers - 2 * l_walls, 0.0, h_ceiling_chamber),
            Point{3,Float64}(offset_inner + l_chambers - 2 * l_walls, 0.0, h_ceiling_channel),
            Point{3,Float64}(offset_inner + l_chambers + l_gaps, 0.0, h_ceiling_channel),
        ]
        append!(V_corners_inner, V_repeated_chambers_inner)
    end

    # --- Last chamber inner ---
    V_last_chamber_inner = [
        Point{3,Float64}(V_corners_inner[end][1], 0.0, h_ceiling_chamber),
        Point{3,Float64}(V_corners_inner[end][1] + l_end_chamber - l_walls - l_end_wall, 0.0, h_ceiling_chamber),
        Point{3,Float64}(V_corners_inner[end][1] + l_end_chamber - l_walls - l_end_wall, 0.0, h_base)
    ]
    append!(V_corners_inner, V_last_chamber_inner)

    # --- Interpolate points ---
    must_points_inner = collect(1:length(V_corners_inner))
    V_boundary_inner = evenly_space(V_corners_inner, pointSpacing_stl;
        close_loop=true, spline_order=2,
        must_points=must_points_inner)

    return V_boundary_inner, l_pneunet
end

"""
    build_boundaries_mould_bottom(
    pointSpacing_stl,   
    n_chambers,     
    h_full,      
    h_base,         
    h_ceiling_channel, 
    h_floor_gap,       
    h_ceiling_chamber,
    l_first_chamber,   
    l_first_wall,    
    l_gaps,         
    l_chambers,      
    l_walls,      
    l_end_wall,     
    l_end_chamber,  
    d_full,   
    d_side    
    )

Creates outer boundaries of pneunet which are extruded and regiontrimeshed for bottom mould. 
Similar to build_boundaries() but does not create inner boundaries

# Returns
Vector of vertices, float 
"""

function build_boundaries_mould_bottom(
    pointSpacing_stl,
    n_chambers,
    h_full,
    h_base,
    h_ceiling_channel,
    h_floor_gap,
    h_ceiling_chamber,
    l_first_chamber,
    l_first_wall,
    l_gaps,
    l_chambers,
    l_walls,
    l_end_wall,
    l_end_chamber,
    d_full,
    d_side
)

    l_pneunet = l_first_chamber + l_gaps * (n_chambers - 1) + l_chambers * (n_chambers - 2) + l_end_chamber # length of pneunet

    # --- First chamber outer ---
    V_first_chamber_outer = [
        Point{3,Float64}(0.0, 0.0, h_base),
        Point{3,Float64}(0.0, 0.0, h_full),
        Point{3,Float64}(l_first_chamber, 0.0, h_full),
        Point{3,Float64}(l_first_chamber, 0.0, h_floor_gap),
        Point{3,Float64}(l_first_chamber + l_gaps, 0.0, h_floor_gap),
    ]
    V_corners_outer = copy(V_first_chamber_outer)

    # --- Repeated chambers ---
    for i ∈ 1:(n_chambers-2)
        offset_outer = V_first_chamber_outer[end][1] + (Float64(i - 1) * (l_chambers + l_gaps))
        V_repeated_chambers_outer = [
            Point{3,Float64}(offset_outer, 0.0, h_full),
            Point{3,Float64}(offset_outer + l_chambers, 0.0, h_full),
            Point{3,Float64}(offset_outer + l_chambers, 0.0, h_floor_gap),
            Point{3,Float64}(offset_outer + l_chambers + l_gaps, 0.0, h_floor_gap),
        ]
        append!(V_corners_outer, V_repeated_chambers_outer)
    end

    # --- Last chamber outer ---
    V_last_chamber_outer = [
        Point{3,Float64}(V_corners_outer[end][1], 0.0, h_full),
        Point{3,Float64}(V_corners_outer[end][1] + l_end_chamber, 0.0, h_full),
        Point{3,Float64}(V_corners_outer[end][1] + l_end_chamber, 0.0, h_base),
    ]
    append!(V_corners_outer, V_last_chamber_outer)

    # --- Interpolate points ---
    must_points_outer = collect(1:length(V_corners_outer))
    V_boundary_outer = evenly_space(V_corners_outer, pointSpacing_stl;
        close_loop=true, spline_order=2,
        must_points=must_points_outer)

    return V_boundary_outer, l_pneunet # Vector of vertices, float 
end

"""
    extrude_boundaries_mould(V_boundary, l_shape, d_full, pointSpacing_stl)

Creates extruded surfaces for bottom mould and inner mould. 
Similar to extrude_boundaries() but deletes the bottom edge of V_boundary to allow for mould geometry to be added

# Returns
Face and vertex vectors
"""

function extrude_boundaries_mould(V_boundary, l_shape, d_full, pointSpacing_stl)
    # Extrusion vector in Y-direction
    n = Vec3{Float64}(0.0, 1.0, 0.0)

    # Delete bottom part of curve
    V_boundary_no_bottom = copy(V_boundary) # to prevent changing the overall V_boundary_inner_mi
    deleteat!(V_boundary_no_bottom, length(V_boundary_no_bottom)-floor(Int, l_shape / pointSpacing_stl)+2:length(V_boundary_no_bottom))

    # --- Outer extrusion ---
    num_steps_width = 1 + ceil(Int, d_full / pointSpacing_stl)
    F_extrude, V_extrude = extrudecurve(
        V_boundary_no_bottom;
        extent=d_full,
        direction=:both,
        n=n,
        num_steps=num_steps_width,
        close_loop=false,
        face_type=:forwardslash
    )

    return F_extrude, V_extrude # Face and vertex vectors
end

"""
    build_outer_bottom_mould(l_pneunet, h_full, h_base, d_full, t_mould, pointSpacing_stl)

Creates outside surfaces of bottom mould. 
Uses extrudecurve and regiontrimesh to create box-like shape
Bottom surface which connects inner and outer surfaces of mould is not created here, instead this surface will be created in build_bottom_region()

# Returns
Face and vertex vectors
"""

function build_outer_bottom_mould(l_pneunet, h_full, h_base, d_full, t_mould, pointSpacing_stl)
    # Create rectangle outside inner mould surfaces at y=0
    V_outer_mould_bottom_corners = [
        Point{3,Float64}(-t_mould, 0.0, h_base),
        Point{3,Float64}(-t_mould, 0.0, h_full + t_mould),
        Point{3,Float64}(l_pneunet + t_mould, 0.0, h_full + t_mould),
        Point{3,Float64}(l_pneunet + t_mould, 0.0, h_base)
    ]
    must_points = collect(1:length(V_outer_mould_bottom_corners))
    V_outer_mould_bottom = evenly_space(V_outer_mould_bottom_corners, pointSpacing_stl;
        close_loop=true, spline_order=2,
        must_points=must_points)

    # Project boundaries into x–z plane for regiontrimesh
    V_xy_outer = [Point{3,Float64}(p[1], p[3], 0.0) for p in V_outer_mould_bottom]

    # Reverse orientation for triangulation
    V_xy_reversed_outer = (reverse(V_xy_outer),)

    # Triangulate region
    R = ([1],)
    F_outer, V_tri_outer = regiontrimesh(V_xy_reversed_outer, R, pointSpacing_stl)

    # Back faces
    F_back_outer = copy(F_outer)

    # Front faces (reverse orientation)

    F_front_outer = [reverse(f) for f in F_back_outer]

    # Position vertices in 3D space
    V_back_outer = [Point{3,Float64}(p[1], (d_full + 2 * t_mould) / 2.0, p[2]) for p in V_tri_outer]
    V_front_outer = [Point{3,Float64}(p[1], -(d_full + 2 * t_mould) / 2.0, p[2]) for p in V_tri_outer]

    # Delete bottom part of curve and extrude, this surface will be created in build_bottom_region()
    deleteat!(V_outer_mould_bottom, length(V_outer_mould_bottom)-floor(Int, (l_pneunet + 2 * t_mould) / pointSpacing_stl)+2:length(V_outer_mould_bottom))
    n = Vec3{Float64}(0.0, 1.0, 0.0) # extrusion vector
    num_steps_width = 1 + ceil(Int, (d_full + 2 * t_mould) / pointSpacing_stl)
    F_extrude_outer, V_extrude_outer = extrudecurve(
        V_outer_mould_bottom;
        extent=d_full + 2 * t_mould,
        direction=:both,
        n=n,
        num_steps=num_steps_width,
        close_loop=false,
        face_type=:forwardslash
    )

    F_outer_mould_bottom, V_outer_mould_bottom = joingeom(F_back_outer, V_back_outer, F_front_outer, V_front_outer, F_extrude_outer, V_extrude_outer)

    return F_outer_mould_bottom, V_outer_mould_bottom # Face and vertex vectors
end

"""
    build_bottom_region(V_back_outer_mb, V_front_outer_mb, V_extrude_outer_mb, V_outer_mould_bottom, h_base)

Take points of V_back_outer_mb, V_front_outer_mb, V_extrude_outer_mb, V_outer_mould_bottom which are at z=h_base
Regiontrimeshes between curves. 
Also includes holes to attach inner mould to outer mould for stability and accuracy. 

# Returns
Face and vertex vectors
"""

function build_bottom_region(V_back_outer_mb, V_front_outer_mb, V_extrude_outer_mb, V_outer_mould_bottom, h_base)
    # Find points at z=h_base, creates inner and outer boundary
    V_inner_all = [V_back_outer_mb; V_front_outer_mb; V_extrude_outer_mb]
    ind_inner_bottom = findall(p -> isapprox(p[3], h_base; atol=1e-6), V_inner_all)
    V_inner_bottom = V_inner_all[ind_inner_bottom]
    V_inner_bottom = reorder_rectangular_boundary(V_inner_bottom, :xy)

    ind_outer_bottom = findall(p -> isapprox(p[3], h_base; atol=1e-6), V_outer_mould_bottom)
    V_outer_bottom = V_outer_mould_bottom[ind_outer_bottom]
    V_outer_bottom = reorder_rectangular_boundary(V_outer_bottom, :xy)

    # Creates 2 sets of circle points for holes
    V_hole = circlepoints(r_hole, max(5, ceil(Int, 2 * 3 * r_hole / pointSpacing_stl)); dir=:acw)
    V_hole_on_plane = [Point{3,Float64}(-t_mould / 2 + p[1], p[2], h_base) for p in V_hole] # translate to z=h_base
    V_hole_inset = [Point{3,Float64}(-t_mould / 2 + p[1], p[2], h_base + d_hole) for p in V_hole] # translate to depth of hole
    V_hole_on_plane2 = [Point{3,Float64}(l_pneunet + t_mould / 2 + p[1], p[2], h_base) for p in V_hole] # same as first hole
    V_hole_inset2 = [Point{3,Float64}(l_pneunet + t_mould / 2 + p[1], p[2], h_base + d_hole) for p in V_hole]

    # Regiontrimesh setup
    VT = (V_outer_bottom, V_inner_bottom, V_hole_on_plane, V_hole_on_plane2)
    R = ([1, 2, 3, 4],)
    P = (pointSpacing_stl,)
    n = Vec3{Float64}(0.0, 0.0, 1.0) # normal vector to shape face

    F_bottom_region_mb, V_bottom_region_mb = regiontrimesh(VT, R, P)

    # Extrusion for hole 1
    F_hole_extrude, V_hole_extrude = extrudecurve(
        V_hole_on_plane;
        extent=d_hole,
        direction=:positive,
        n=n,
        num_steps=ceil(Int, d_hole / pointSpacing_stl) + 1,
        close_loop=true,
        face_type=:forwardslash
    )

    # Extrusion for hole 2
    F_hole_extrude2, V_hole_extrude2 = extrudecurve(
        V_hole_on_plane2;
        extent=d_hole,
        direction=:positive,
        n=n,
        num_steps=ceil(Int, d_hole / pointSpacing_stl) + 1,
        close_loop=true,
        face_type=:forwardslash
    )

    # Regiontrimesh for end of hole 1
    VT = (V_hole_inset,)
    R = ([1],)
    F_hole_inset, V_hole_inset = regiontrimesh(VT, R, P)

    # Regiontrimesh for end of hole 2
    VT = (V_hole_inset2,)
    F_hole_inset2, V_hole_inset2 = regiontrimesh(VT, R, P)

    # Join all geometry
    F_bottom_region, V_bottom_region = joingeom(F_bottom_region_mb, V_bottom_region_mb, F_hole_extrude, V_hole_extrude, F_hole_extrude2, V_hole_extrude2, F_hole_inset, V_hole_inset, F_hole_inset2, V_hole_inset2)

    return F_bottom_region, V_bottom_region # Face and vertex vectors
end

"""
    build_mould_bottom_for_stl()

Creates entire geometry for bottom mould, using several sub-functions


# Returns
Face and vertex vectors
"""

function build_mould_bottom_for_stl()

    # Use existing geometry processes
    V_boundary_outer, l_pneunet = build_boundaries_mould_bottom(pointSpacing_stl, n_chambers,
        h_full, h_base, h_ceiling_channel, h_floor_gap, h_ceiling_chamber,
        l_first_chamber, l_first_wall, l_gaps, l_chambers, l_walls,
        l_end_wall, l_end_chamber,
        d_full, d_side)

    F_back_outer_mb, V_back_outer_mb, F_front_outer_mb, V_front_outer_mb = build_endcaps(V_boundary_inner, V_boundary_outer, d_full, d_side, pointSpacing_stl, h_floor_gap, h_ceiling_channel)
    F_extrude_outer_mb, V_extrude_outer_mb = extrude_boundaries_mould(V_boundary_outer, l_pneunet, d_full, pointSpacing_stl)
    F_outer_mould_bottom, V_outer_mould_bottom = build_outer_bottom_mould(l_pneunet, h_full, h_base, d_full, t_mould, pointSpacing_stl)

    F_bottom_region_mb, V_bottom_region_mb = build_bottom_region(V_back_outer_mb, V_front_outer_mb, V_extrude_outer_mb, V_outer_mould_bottom, h_base)

    F_mould_bottom, V_mould_bottom, Cs_mould_bottom = joingeom(F_extrude_outer_mb, V_extrude_outer_mb, F_outer_mould_bottom, V_outer_mould_bottom, F_bottom_region_mb, V_bottom_region_mb, F_back_outer_mb, V_back_outer_mb, F_front_outer_mb, V_front_outer_mb)

    # # # # --- Merge duplicate vertices ---
    Fs_mould_bottom, Vs_mould_bottom = mergevertices(F_mould_bottom, V_mould_bottom)

    return Fs_mould_bottom, Vs_mould_bottom
end

"""
    build_mould_top_for_stl()

Creates entire geometry for top mould. 
Uses regiontrimesh and extrudecurve. 
Includes pins to allow for accurate alignment to bottom mould. 

# Returns
Face and vertex vectors
"""

function build_mould_top_for_stl()
    # Outer boundary corners
    V_outer_mould_top_corners = [
        Point{3,Float64}(-t_mould, -t_mould, 0.0),
        Point{3,Float64}(l_pneunet + t_mould, -t_mould, 0.0),
        Point{3,Float64}(l_pneunet + t_mould, d_full + t_mould, 0.0),
        Point{3,Float64}(-t_mould, d_full + t_mould, 0.0)
    ]
    
    # Inner boundary corners
    V_inner_mould_top_corners = [
        Point{3,Float64}(0.0, 0.0, 0.0),
        Point{3,Float64}(l_pneunet, 0.0, 0.0),
        Point{3,Float64}(l_pneunet, d_full, 0.0),
        Point{3,Float64}(0.0, d_full, 0.0)
    ]

    # Interpolate boundaries
    must_points = collect(1:length(V_outer_mould_top_corners))
    V_outer_mould_top = evenly_space(V_outer_mould_top_corners, pointSpacing_stl;
        close_loop=true, spline_order=2,
        must_points=must_points)
    must_points = collect(1:length(V_inner_mould_top_corners))
    V_inner_mould_top = evenly_space(V_inner_mould_top_corners, pointSpacing_stl;
        close_loop=true, spline_order=2,
        must_points=must_points)

    # extrude outer boundary
    # Extrusion vector in Y-direction
    n = Vec3{Float64}(0.0, 0.0, 1.0)
    num_steps_width = 1 + ceil(Int, h_base + h_sll + t_mould / pointSpacing_stl)
    F_extrude_outer_tm, V_extrude_outer_tm = extrudecurve(
        V_outer_mould_top;
        extent=h_base + h_sll + t_mould,
        direction=:positive,
        n=n,
        num_steps=num_steps_width,
        close_loop=true,
        face_type=:forwardslash
    )

    # extruse inner boundary
    num_steps_width = 1 + ceil(Int, h_base + h_sll / pointSpacing_stl)
    F_extrude_inner_tm, V_extrude_inner_tm = extrudecurve(
        V_inner_mould_top;
        extent=h_base + h_sll,
        direction=:positive,
        n=n,
        num_steps=num_steps_width,
        close_loop=true,
        face_type=:forwardslash
    )

    # regiontrimesh end of extrudecurve outer
    V_outer_top_mould_bottom = [Point{3,Float64}(p[1], p[2], h_sll + h_base + t_mould) for p in V_outer_mould_top]
    VT = (V_outer_top_mould_bottom,)
    R = ([1],)
    P = (pointSpacing_stl,)
    F_outer_top_mould_bottom, V_outer_top_mould_bottom = regiontrimesh(VT, R, P)

    # regiontrimesh end of extrudecurve outer
    V_inner_top_mould_bottom = [Point{3,Float64}(p[1], p[2], h_sll + h_base) for p in V_inner_mould_top]
    VT = (V_inner_top_mould_bottom,)
    F_inner_top_mould_bottom, V_inner_top_mould_bottom = regiontrimesh(VT, R, P)

    # Create geometry of 2 pins
    V_hole = circlepoints(r_pin, max(5, ceil(Int, 2 * 3 * r_pin / pointSpacing_stl)); dir=:acw)
    V_hole_on_plane = [Point{3,Float64}(-t_mould / 2 + p[1], d_full / 2.0 + p[2], 0.0) for p in V_hole] # translate to z=0.0
    V_hole_inset = [Point{3,Float64}(-t_mould / 2 + p[1], d_full / 2.0 + p[2], -d_pin) for p in V_hole] # translate to height of pin
    V_hole_on_plane2 = [Point{3,Float64}(l_pneunet + t_mould / 2 + p[1], d_full / 2.0 + p[2], 0.0) for p in V_hole] # same as first pin
    V_hole_inset2 = [Point{3,Float64}(l_pneunet + t_mould / 2 + p[1], d_full / 2.0 + p[2], -d_pin) for p in V_hole]

    # regiontrimesh between inner and outer boundaries, including pins
    VT = (V_outer_mould_top, V_inner_mould_top, V_hole_on_plane, V_hole_on_plane2)
    R = ([1, 2, 3, 4],)
    P = (pointSpacing_stl,)
    n = Vec3{Float64}(0.0, 0.0, 1.0) # normal vector to shape face
    F_bottom_region_mt, V_bottom_region_mt = regiontrimesh(VT, R, P)

    # Extrude pin 1
    F_hole_extrude, V_hole_extrude = extrudecurve(
        V_hole_on_plane;
        extent=d_pin,
        direction=:negative,
        n=n,
        num_steps=ceil(Int, d_hole / pointSpacing_stl) + 1,
        close_loop=true,
        face_type=:forwardslash
    )

    # Extrude pin 2
    F_hole_extrude2, V_hole_extrude2 = extrudecurve(
        V_hole_on_plane2;
        extent=d_pin,
        direction=:negative,
        n=n,
        num_steps=ceil(Int, d_hole / pointSpacing_stl) + 1,
        close_loop=true,
        face_type=:forwardslash
    )

    # Regiontrimesh top of pin 1
    VT = (V_hole_inset,)
    R = ([1],)
    F_hole_inset, V_hole_inset = regiontrimesh(VT, R, P)

    # Regiontrimesh top of pin 2
    VT = (V_hole_inset2,)
    F_hole_inset2, V_hole_inset2 = regiontrimesh(VT, R, P)

    # Merge geometry
    Fs_mould_top, Vs_mould_top, Cs_mould_top = joingeom(F_extrude_outer_tm, V_extrude_outer_tm, F_extrude_inner_tm, V_extrude_inner_tm, F_bottom_region_mt, V_bottom_region_mt, F_outer_top_mould_bottom, V_outer_top_mould_bottom, F_inner_top_mould_bottom, V_inner_top_mould_bottom, F_hole_extrude, V_hole_extrude, F_hole_extrude2, V_hole_extrude2, F_hole_inset, V_hole_inset, F_hole_inset2, V_hole_inset2)
    Fs_mould_top, Vs_mould_top = mergevertices(Fs_mould_top, Vs_mould_top)

    return Fs_mould_top, Vs_mould_top # Face and vertex vectors
end

"""
    build_mould_inner_for_stl()

Creates entire geometry for inner mould (mi), using sub-fuctions. 
Includes pins to allow for accurate alignment to bottom mould. 

# Returns
Face and vertex vectors


# Arguments
- '': 

# Returns
Face and vertex vectors
"""
function build_mould_inner_for_stl()
    # Generate pneunet inner boundary
    V_boundary_inner_mi, l_pneunet = build_boundaries_for_stl(pointSpacing_stl, n_chambers,
        h_full, h_base, h_ceiling_channel, h_floor_gap, h_ceiling_chamber,
        l_first_chamber, l_first_wall, l_gaps, l_chambers, l_walls,
        l_end_wall, l_end_chamber,
        d_full, d_side)

    # extrude boundaries, representing the inner extusions of pneunet
    l_pneunet_inner = l_pneunet - l_end_wall
    F_extrude_mi, V_extrude_mi = extrude_boundaries_mould(V_boundary_inner_mi, l_pneunet_inner, (d_full - 2.0 * d_side), pointSpacing_stl)

    # Create endcaps, representing the inner endcaps of pneunet
    _, _, _, _, F_back_inner_mi, V_back_inner_mi, F_front_inner_mi, V_front_inner_mi = build_endcaps(V_boundary_inner_mi, V_boundary_outer, d_full, d_side, pointSpacing_stl, h_floor_gap, h_ceiling_channel)

    # Find points at z=h_base and create rectangular boundary
    V_inner_all_mi = [V_back_inner_mi; V_front_inner_mi; V_extrude_mi]
    V_inner_bottom_mi = [p for p in V_inner_all_mi if isapprox(p[3], h_base; atol=1e-6)]
    V_inner_bottom_mi = reorder_rectangular_boundary(V_inner_bottom_mi, :xy)

    # Build inner mould support surfaces (connects to bottom mould), 2 support regions
    V_mi_support_corners = [
        Point{3,Float64}(0.0, (d_full - 2.0 * d_side) / 2.0, h_base),
        Point{3,Float64}(-t_mould, (d_full - 2.0 * d_side) / 2.0, h_base),
        Point{3,Float64}(-t_mould, -(d_full - 2.0 * d_side) / 2.0, h_base),
        Point{3,Float64}(0.0, -(d_full - 2.0 * d_side) / 2.0, h_base),
    ]
    must_points = collect(1:length(V_mi_support_corners))
    V_mi_support_boundary = evenly_space(V_mi_support_corners, pointSpacing_stl;
        close_loop=false, spline_order=2,
        must_points=must_points)
    V_mi_support1_existing = [p for p in V_inner_bottom_mi if isapprox(p[1], 0.0; atol=1e-6)]
    V_mi_support1 = [V_mi_support_boundary; V_mi_support1_existing]
    V_mi_support1 = reorder_rectangular_boundary(V_mi_support1, :xy)

    V_mi_support_corners2 = [
        Point{3,Float64}(l_pneunet - l_end_wall, (d_full - 2.0 * d_side) / 2.0, h_base),
        Point{3,Float64}(l_pneunet + t_mould, (d_full - 2.0 * d_side) / 2.0, h_base),
        Point{3,Float64}(l_pneunet + t_mould, -(d_full - 2.0 * d_side) / 2.0, h_base),
        Point{3,Float64}(l_pneunet - l_end_wall, -(d_full - 2.0 * d_side) / 2.0, h_base),
    ]
    must_points = collect(1:length(V_mi_support_corners2))
    V_mi_support_boundary2 = evenly_space(V_mi_support_corners2, pointSpacing_stl;
        close_loop=false, spline_order=2,
        must_points=must_points)
    V_mi_support2_existing = [p for p in V_inner_bottom_mi if isapprox(p[1], l_pneunet - l_end_wall; atol=1e-6)]
    V_mi_support2 = [V_mi_support_boundary2; V_mi_support2_existing]
    V_mi_support2 = reorder_rectangular_boundary(V_mi_support2, :xy)

    # Creates points for 2 pins to connect to bottom mould
    V_pin = circlepoints(r_pin, max(5, ceil(Int, 2 * 3 * r_pin / pointSpacing_stl)); dir=:acw)
    V_pin_on_plane = [Point{3,Float64}(-t_mould / 2 + p[1], p[2], h_base) for p in V_pin] # translate to z=h_base and pin 1 location
    V_pin_inset = [Point{3,Float64}(-t_mould / 2 + p[1], p[2], h_base + d_pin) for p in V_pin] # translate to top of pin and pin 1 location
    V_pin_on_plane2 = [Point{3,Float64}(l_pneunet + t_mould / 2 + p[1], p[2], h_base) for p in V_pin] # same as pin 1 
    V_pin_inset2 = [Point{3,Float64}(l_pneunet + t_mould / 2 + p[1], p[2], h_base + d_pin) for p in V_pin]

    # regiontrimesh support region 1
    VT = (V_mi_support1, V_pin_on_plane)
    R = ([1, 2],)
    P = (pointSpacing_stl,)
    n = Vec3{Float64}(0.0, 0.0, 1.0) # normal vector to shape face
    F_support_region_mi, V_support_region_mi = regiontrimesh(VT, R, P)

    # regiontrimesh support region 2
    VT = (V_mi_support2, V_pin_on_plane2)
    R = ([1, 2],)
    P = (pointSpacing_stl,)
    F_support_region2_mi, V_support_region2_mi = regiontrimesh(VT, R, P)

    # extrude pin 1 upwards
    F_pin_extrude, V_pin_extrude = extrudecurve(
        V_pin_on_plane;
        extent=d_pin,
        direction=:positive,
        n=n,
        num_steps=ceil(Int, d_hole / pointSpacing_stl) + 1,
        close_loop=true,
        face_type=:forwardslash
    )
    # extrude pin 2 upwards
    F_pin_extrude2, V_pin_extrude2 = extrudecurve(
        V_pin_on_plane2;
        extent=d_pin,
        direction=:positive,
        n=n,
        num_steps=ceil(Int, d_hole / pointSpacing_stl) + 1,
        close_loop=true,
        face_type=:forwardslash
    )

    # regiontrimesh top of pin 1
    VT = (V_pin_inset,)
    R = ([1],)
    F_pin_inset, V_pin_inset = regiontrimesh(VT, R, P)


    # regiontrimesh top of pin 1
    VT = (V_pin_inset2,)
    F_pin_inset2, V_pin_inset2 = regiontrimesh(VT, R, P)

    # extrude outmost boundary of inner mould up
    V_side1_mi = [p for p in V_inner_bottom_mi if isapprox(p[2], (d_full - 2 * d_side) / 2.0; atol=1e-6)]
    V_side2_mi = [p for p in V_inner_bottom_mi if isapprox(p[2], -(d_full - 2 * d_side) / 2.0; atol=1e-6)]
    V_outer_mi = [V_mi_support_boundary; V_mi_support_boundary2; V_side1_mi; V_side2_mi]
    V_outer_mi = reorder_rectangular_boundary(V_outer_mi, :xy)
    n = Vec3{Float64}(0.0, 0.0, 1.0)
    num_steps_width = 1 + ceil(Int, t_mould / pointSpacing_stl)
    F_bottom_extrude_mi, V_bottom_extrude_mi = extrudecurve(
        V_outer_mi;
        extent=t_mould,
        direction=:negative,
        n=n,
        num_steps=num_steps_width,
        close_loop=true,
        face_type=:forwardslash
    )

    # regiontrimesh top of extrusion
    V_outer_mi_bottom = [Point{3,Float64}(p[1], p[2], h_base - t_mould) for p in V_outer_mi]
    VT = (reverse(V_outer_mi_bottom),)
    R = ([1],)
    P = (pointSpacing_stl,)
    F_bottom_mi, V_bottom_mi = regiontrimesh(VT, R, P)

    # Merge geometry
    Fs_mould_inner, Vs_mould_inner, Cs_mould_inner = joingeom(F_back_inner_mi, V_back_inner_mi, F_front_inner_mi, V_front_inner_mi, F_extrude_mi, V_extrude_mi, F_bottom_mi, V_bottom_mi, F_bottom_extrude_mi, V_bottom_extrude_mi, F_support_region_mi, V_support_region_mi, F_support_region2_mi, V_support_region2_mi, F_pin_extrude, V_pin_extrude, F_pin_extrude2, V_pin_extrude2, F_pin_inset, V_pin_inset, F_pin_inset2, V_pin_inset2)
    Fs_mould_inner, Vs_mould_inner = mergevertices(Fs_mould_inner, Vs_mould_inner)

    return Fs_mould_inner, Vs_mould_inner # Face and vertex vectors
end
# ====================================================================

# ====================================================================
# 11 GEOMETRY CREATION SCRIPT

# Create geometry boundaries
V_boundary_inner, V_boundary_outer, l_pneunet = build_boundaries(pointSpacing, n_chambers,
    h_full, h_base, h_ceiling_channel, h_floor_gap, h_ceiling_chamber,
    l_first_chamber, l_first_wall, l_gaps, l_chambers, l_walls,
    l_end_wall, l_end_chamber,
    d_full, d_side)

# Create extruded faces
F_extrude_inner, V_extrude_inner, F_extrude_outer, V_extrude_outer = extrude_boundaries(V_boundary_inner, V_boundary_outer, d_full, d_side, pointSpacing)

# Create end faces
F_back_outer, V_back_outer, F_front_outer, V_front_outer, F_back_inner, V_back_inner, F_front_inner, V_front_inner = build_endcaps(V_boundary_inner, V_boundary_outer, d_full, d_side, pointSpacing, h_floor_gap, h_ceiling_channel)

# Create elements of main part
E, V, CE, Fb, Cb = build_main_body(F_extrude_outer, V_extrude_outer,
    F_extrude_inner, V_extrude_inner,
    F_back_outer, V_back_outer,
    F_front_outer, V_front_outer,
    F_back_inner, V_back_inner,
    F_front_inner, V_front_inner,
    l_first_wall, l_first_chamber, l_walls,
    h_base, h_ceiling_chamber)

# Create elements of strain limiting layer (sll)
E_sll, V_sll, CE_sll, Fb_sll, Cb_sll = build_sll_mesh(F_extrude_outer, V_extrude_outer, h_sll, d_full, l_pneunet, pointSpacing)
# ====================================================================

# ====================================================================
# 12 FEBio SIMULATION SCRIPT

# FEBio Preparation
nodes,
elements_main, elements_sll,
elements_paper, F_paper, mesh_paper,
Fb_all, Fb_internal, Fb_extrude_outer, Fb_fixed_face_left,
Fb_faces_contact_primary, Fb_faces_contact_secondary =
    FEBio_nodes_elements(saveDir, filename,
        V, V_sll, E, E_sll, Fb, Fb_sll, Cb,
        pointSpacing, n_chambers,
        l_first_chamber, l_chambers, l_gaps)

# Create .feb file and run FEBio simulation
if runSimulation == 1
    run_simulation(
        nodes,
        elements_main,
        elements_sll,
        elements_paper,
        Fb_internal,
        Fb_fixed_face_left,
        Fb_faces_contact_primary,
        Fb_faces_contact_secondary,
        pointSpacing, n_chambers,
        l_pneunet, h_full, h_sll,
        P, number, saveDir, filename
    )
end
# ====================================================================

# ====================================================================
# 13 GLMakie plot script
if runPlot == 1
    fig = Figure(size=(1200, 1200))
    ax1 = AxisGeom(fig[1, 1], title="Pneunet Geometry")
    ax1.aspect = :data

    # # Use the following to adjust plot appearaance
    # ax1.xticksvisible = false
    # ax1.yticksvisible = false
    # ax1.zticksvisible = false
    # ax1.xticklabelsvisible = false
    # ax1.yticklabelsvisible = false
    # ax1.zticklabelsvisible = false
    # ax1.xlabelvisible = false
    # ax1.ylabelvisible = false
    # ax1.zlabelvisible = false
    # ax1.xgridvisible = false
    # ax1.ygridvisible = false
    # ax1.zgridvisible = false
    # ax1.xspinesvisible = false
    # ax1.yspinesvisible = false
    # ax1.zspinesvisible = false

    # # View inner and outer boundary
    # lines!(ax1, V_boundary_inner; color = :orange, linewidth = 3)
    # lines!(ax1, V_boundary_outer; color = :orange, linewidth = 3)

    # # View each face set of pneunet individually
    # meshplot!(ax1, F_extrude_outer, V_extrude_outer, color=(:red, 0.1), transparency=true)
    # meshplot!(ax1, F_back_outer, V_back_outer,  color=(:red, 0.1), transparency=true)
    # meshplot!(ax1, F_front_outer, V_front_outer,  color=(:red, 0.1), transparency=true)
    # meshplot!(ax1, F_extrude_inner, V_extrude_inner, color=:yellow)
    # meshplot!(ax1, F_back_inner, V_back_inner, color=:yellow)
    # meshplot!(ax1, F_front_inner, V_front_inner, color=:yellow)
    meshplot!(ax1, Fb_sll, V_sll, color=:blue)


    # View overall pneunet and sll
    # meshplot!(ax1, Fb_all, nodes; color=:white)

    # # View internal surface (upon which pressure acts)
    # meshplot!(ax1, Fb_internal, nodes)

    # # View 2D shell layer (paper)
    # if paper == 1
    #     meshplot!(ax1, mesh_paper; color=:blue) # plot sll
    # end

    # # View contact faces
    # for i = 1:n_chambers-1
    #     meshplot!(ax1, Fb_faces_contact_primary[i], V; color=:yellow)
    #     meshplot!(ax1, Fb_faces_contact_secondary[i], V; color=:blue)
    # end

    # # View points on top and bottom end edges of pneunet (used in Excel output)
    # V_end_bottom = [
    #     v for v in nodes
    #     if isapprox(v[3], -h_sll; atol=1E-6) &&
    #     isapprox(v[1], l_pneunet; atol=1E-6)
    # ]
    # V_end_top = [
    #     v for v in nodes
    #     if isapprox(v[3], h_full; atol=1E-6) &&
    #     isapprox(v[1], l_pneunet; atol=1E-6)
    # ]
    # scatter!(ax1, V_end_bottom; color=:red, markersize=10)
    # scatter!(ax1, V_end_top; color=:blue, markersize=10)

    screen = display(GLMakie.Screen(), fig) # display plot in window
end
# ====================================================================

# ====================================================================
# 14 VISUALIZATION SCRIPT (ADJUSTABLE PARAMETERS)

# Visualisation - number of chambers
if visualSlider == 1
    fig = Figure(size=(1200, 1000))
    ax1 = Axis3(fig[1, 1], title="Refinement of number of chambers, n = 5", titlesize=50, titlegap=-20)
    ax1.aspect = :data

    # Adjustments to plot appearaance
    ax1.xticksvisible = false
    ax1.yticksvisible = false
    ax1.zticksvisible = false
    ax1.xticklabelsvisible = false
    ax1.yticklabelsvisible = false
    ax1.zticklabelsvisible = false
    ax1.xlabelvisible = false
    ax1.ylabelvisible = false
    ax1.zlabelvisible = false
    ax1.xgridvisible = false
    ax1.ygridvisible = false
    ax1.zgridvisible = false
    ax1.xspinesvisible = false
    ax1.yspinesvisible = false
    ax1.zspinesvisible = false

    # Initial geometry
    F_extrude_inner, V_extrude_inner, F_extrude_outer, V_extrude_outer, F_back_outer, V_back_outer, F_back_inner, V_front_outer, F_front_inner, V_back_inner, F_front_outer, V_front_inner = build_geometry_for_visualization(pointSpacing, n_chambers,
        h_full, h_base, h_ceiling_channel, h_floor_gap, h_ceiling_chamber,
        l_first_chamber, l_first_wall, l_gaps, l_chambers, l_walls,
        l_end_wall, l_end_chamber,
        d_full, d_side)
    E_sll, V_sll, CE_sll, Fb_sll, Cb_sll = build_sll_mesh(F_extrude_outer, V_extrude_outer, h_sll, d_full, l_pneunet, pointSpacing)

    # Store plots
    hp = [
        meshplot!(ax1, F_extrude_outer, V_extrude_outer, color=:red),
        meshplot!(ax1, F_back_outer, V_back_outer, color=:red),
        meshplot!(ax1, F_front_outer, V_front_outer, color=:red),
        meshplot!(ax1, Fb_sll, V_sll; color=:yellow)
    ]

    # Slider
    stepRange = 2:10 # number of chambers 2 to 10
    hSlider1 = Slider(fig[2, :], range=stepRange, startvalue=5, linewidth=30) # create slider

    on(hSlider1.value) do new_chambers
        # Recompute geometry
        F_extrude_inner, V_extrude_inner, F_extrude_outer, V_extrude_outer, F_back_outer, V_back_outer, F_back_inner, V_front_outer, F_front_inner, V_back_inner, F_front_outer, V_front_inner = build_geometry_for_visualization(pointSpacing, new_chambers,
            h_full, h_base, h_ceiling_channel, h_floor_gap, h_ceiling_chamber,
            l_first_chamber, l_first_wall, l_gaps, l_chambers, l_walls,
            l_end_wall, l_end_chamber,
            d_full, d_side)

        E_sll, V_sll, CE_sll, Fb_sll, Cb_sll = build_sll_mesh(F_extrude_outer, V_extrude_outer, h_sll, d_full, l_pneunet, pointSpacing)

        # Update plots
        hp[1][1] = GeometryBasics.Mesh(V_extrude_outer, F_extrude_outer)
        hp[2][1] = GeometryBasics.Mesh(V_back_outer, F_back_outer)
        hp[3][1] = GeometryBasics.Mesh(V_front_outer, F_front_outer)
        hp[4][1] = GeometryBasics.Mesh(Fb_sll, V_sll)
        ax1.title = "Refinement of number of chambers, n = $new_chambers"
    end

    screen = display(GLMakie.Screen(), fig) # display plot in window
    GLMakie.set_title!(screen, "Refinement of number of chambers") # set title
end
# ====================================================================

# ====================================================================
# 15 STL CREATION SCRIPT
if outputStl == 1
    let # to prevent global variables slowing framework
        # # # CONNECTOR .STL FOR 3D PRINTING
        Fs_connector, Vs_connector = build_connector(pointSpacing_stl, r_hole1, r_shaft3, r_bite4, r_point5, h_connector_inset, h_connector2, h_shaft3, h_bite4, h_loft5, h_full, d_full, h_ceiling_chamber, d_side, h_base)
        write_stl_ascii("STLs/connector.stl", Vs_connector, Fs_connector; solid_name="connector")

        # #MAKE 3D PRINTABLE PNEUNET
        Fs_pneunet, Vs_pneunet, F_sll_stl, Vs_sll = build_pneunet_for_stl(pointSpacing_stl, n_chambers,
            h_full, h_base, h_ceiling_channel, h_floor_gap, h_ceiling_chamber,
            l_first_chamber, l_first_wall, l_gaps, l_chambers, l_walls,
            l_end_wall, l_end_chamber,
            d_full, d_side)
        write_stl_ascii("STLs/pneunet.stl", Vs_pneunet, Fs_pneunet; solid_name="pneunet")
        write_stl_ascii("STLs/sll.stl", Vs_sll, F_sll_stl; solid_name="sll")

        # # MAKE MOULDS
        # ## Bottom mould
        Fs_mould_bottom, Vs_mould_bottom = build_mould_bottom_for_stl()
        write_stl_ascii("STLs/mould_bottom.stl", Vs_mould_bottom, Fs_mould_bottom; solid_name="mould_bottom")

        # ## Inside mould
        Fs_mould_inner, Vs_mould_inner = build_mould_inner_for_stl()
        write_stl_ascii("STLs/mould_inner.stl", Vs_mould_inner, Fs_mould_inner; solid_name="mould_inner")

        # ## Top mould
        Fs_mould_top, Vs_mould_top = build_mould_top_for_stl()
        write_stl_ascii("STLs/mould_top.stl", Vs_mould_top, Fs_mould_top; solid_name="mould_top")



        # PLOT GENERATED GEOMETRIES
        fig1 = Figure(size=(1200, 1200))
        ax1 = AxisGeom(fig1[1, 1], title="Connector geometry")
        meshplot!(ax1, Fs_connector, Vs_connector)
        screen1 = display(GLMakie.Screen(), fig1)

        fig2 = Figure(size=(1200, 1200))
        ax2 = AxisGeom(fig2[1, 1], title="Pneunet and sll geometry")
        meshplot!(ax2, Fs_pneunet, Vs_pneunet; color=(:blue, 0.3))
        meshplot!(ax2, F_sll_stl, Vs_sll; color=(:red, 0.1), transparency=true)
        screen2 = display(GLMakie.Screen(), fig2)

        # three moulds plotted together
        fig3 = Figure(size=(1200, 1200))
        ax3 = AxisGeom(fig3[1, 1], title="Moulds")
        meshplot!(ax3, Fs_mould_bottom, Vs_mould_bottom, color=:yellow)
        # screen3 = display(GLMakie.Screen(), fig3)

        # fig3 = Figure(size=(1200, 1200))
        # ax3 = AxisGeom(fig3[1, 1], title="Moulds2")
        meshplot!(ax3, Fs_mould_inner, Vs_mould_inner, color=:red)
        # screen3 = display(GLMakie.Screen(), fig3)

        # fig3 = Figure(size=(1200, 1200))
        # ax3 = AxisGeom(fig3[1, 1], title="Moulds3")
        meshplot!(ax3, Fs_mould_top, Vs_mould_top)
        screen3 = display(GLMakie.Screen(), fig3)
    end
end
# ====================================================================