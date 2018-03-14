module Quadtrees

using Base.Test
import Base.length
using PyPlot

"""
quadtree (of the higher-dimensional equivalent)
T the type of the coordinates
TA the type of the attributes
N number of dimensions
"""

type QT{T,TA,N}
    children :: Vector{QT{T,TA,N}}  # vector of child nodes (empty if node is a leaf)
    # list of coordinates (only non-empty if node is a leaf)
    # points[:,i] coordinates of the i-th point
    points :: Array{T,2}            
    min :: Vector{T}                # minimum of bounding box
    max :: Vector{T}                # maximim of bounding box
    attribs :: Vector{TA}           # additional attributes (only non-empty if node is a leaf)
end

"""create empty quadtree"""
QT(TA::DataType,min::Vector{T}, max::Vector{T}) where T =
    QT(QT{T,TA,size(min,1)}[],Matrix{T}(size(min,1),0),min,max,TA[])

"""create a quadtree"""

QT(points::Array{T,2},attribs::Vector{TA}) where {T,TA} =
    QT(QT{T,TA,size(points,2)}[],points',minimum(points,1)[:],maximum(points,1)[:],attribs)

QT(points::Array{T,2}, min::Vector{T}, max::Vector{T}, attribs::Vector{TA}) where {T,TA} =
    QT(QT{T,TA,size(points,2)}[],points',min,max,attribs)



QTnew(points::Array{T,2},attribs::Vector{TA}) where {T,TA} =
    QT(QT{T,TA,size(points,1)}[],points,minimum(points,2)[:],maximum(points,2)[:],attribs)

QTnew(points::Array{T,2}, min::Vector{T}, max::Vector{T}, attribs::Vector{TA}) where {T,TA} =
    QT(QT{T,TA,size(points,1)}[],points,min,max,attribs)


"""       
             x1
  +----------+ 
  |          |
  |   +      |
  |   y      |
  +----------+
 x0

"""

function inside(x0,x1,y)
    insd = true

    @inbounds for i = 1:length(y)
        insd = insd & (x0[i] <= y[i] <= x1[i])
    end
    return insd
end

"Test if the n-th bit in a is set. The least significant bit is n = 1."
bitget(a,n) = Bool((a & (1 << (n-1))) >> (n-1))





function intersect_(x0,x1,y0,y1)    
    # number of dimensions
    n = size(x0,1)

    intrsct = false
    
    @inbounds for i = 1:2^n
        inside = true
        @inbounds for j = 1:n
            if bitget(i-1, j)
                inside = inside & (x0[j] <= y0[j] <= x1[j])
            else
                inside = inside & (x0[j] <= y1[j] <= x1[j])
            end
        end

        intrsct = intrsct | inside
    end

    return intrsct
end

"""    
Test of the rectanges defined by x0,x1  and y0,y1 intersects
             x1
  +----------+ 
  |          |
  |   +----------+ y1
  |   |      |   |
  +----------+   |
 x0   |          |
      |          |
      +----------+
     y0
"""

function intersect(x0,x1,y0,y1)
    n = size(x0,1)
#    if (n != length(x1)) || (n != length(y0)) || (n != length(y1))
#        throw(ArgumentError("all arguments of intersect must have the same length"))
#    end

    return intersect_(x0,x1,y0,y1) || intersect_(y0,y1,x0,x1)
end

"""
number of points per node
it is always zero for non-leaf nodes
"""
Base.length(qt::QT) = size(qt.points,2)

isleaf(qt) = length(qt.children) == 0

inside(qt::QT,y) = inside(qt.min,qt.max,y)
Base.intersect(qt::QT,y0,y1) = intersect(qt.min,qt.max,y0,y1)
Base.ndims(qt::QT{T,TA,N}) where {T,TA,N} = N

function count(qt::QT)
    if isleaf(qt)
        return length(qt)
    else
        c = 0
        for child in qt.children
            c = c + count(child)
        end

        return c
    end
end    

"""
sucess = add!(qt,x,attrib,max_cap = 10)
Add point `x` with the attribute `attrib` to the quadtree `qt`.
`sucess` is true if `x`is within the bounds of the quadtree node `qt` (otherwise 
false and the point has not been added)
"""
function add!(qt::QT{T,TA,N},x,attrib,max_cap = 10) where {T,TA,N}

    if !inside(qt,x)
        return false
    else                
        if isleaf(qt)
            qt.points  = cat(2,qt.points,x)
            push!(qt.attribs,attrib)
            
            # split if necessary
            rsplit!(qt, max_cap)

            return true
        else
            # try to add to all children and returns on first sucessful
            for child in qt.children
                if add!(child,x,attrib,max_cap)
                    return true
                end
            end

            # bounds of child
            cmin = Vector{T}(N)
            cmax = Vector{T}(N)
            xcenter = (qt.max + qt.min)/2
            
            # create missing child
            @inbounds for i = 1:2^N
                for j = 1:N
                    # all corners of a hypercube
                    if bitget(i-1, j)
                        cmin[j] = qt.min[j]
                        cmax[j] = xcenter[j]                    
                    else
                        cmin[j] = xcenter[j]                    
                        cmax[j] = qt.max[j]
                    end
                end

                if all(cmin .< x .<= cmax)                    
                    child = QT(TA,cmin,cmax)
                    add!(child,x,attrib)
                    push!(qt.children,child)
                    return true
                end
            end
            
            # should never happen
            error("could not add $(x)")
            return false
        end
    end
end

"""
split a single node
"""

function split!(qt::QT{T,TA,N}) where {T,TA,N}
    # N: number of dimenions
    
    if isleaf(qt)
        xcenter = (qt.max + qt.min)/2

        nchildren = 2^N
        qt.children = Vector{QT{T,TA,N}}(nchildren)

        # bounds of child
        cmin = Vector{T}(N)
        cmax = Vector{T}(N)        
        sel = trues(size(qt.points,2))
        nchildreneff = 0
        
        @inbounds for i = 1:nchildren
            sel[:] = true

            for j = 1:N
                # all corners of a hypercube
                if bitget(i-1, j)
                    sel = sel .& (qt.points[j,:] .<= xcenter[j])
                    cmin[j] = qt.min[j]
                    cmax[j] = xcenter[j]                    
                else
                    sel = sel .& (qt.points[j,:] .> xcenter[j])
                    cmin[j] = xcenter[j]                    
                    cmax[j] = qt.max[j]
                end
            end
            
            child = QTnew(qt.points[:,sel],copy(cmin),copy(cmax),qt.attribs[sel])

            # add only children with data
            if length(child) > 0
                 nchildreneff = nchildreneff+1
                 qt.children[nchildreneff] = child
            end
        end

        # trim leaves with no data
        resize!(qt.children,nchildreneff)

        # remove points from node
        qt.points = Matrix{T}(N,0)
    end
end

"""
recursive split
"""

function rsplit!(qt::QT{T,TA,N}, max_cap = 10) where {T,TA,N}


    
    if isleaf(qt)
        if length(qt) < max_cap
            # no enougth points, nothing to do
            return
        end
        
        allequal = true

        @inbounds for i = 2:size(qt.points,2)
            allequal = allequal & (qt.points[:,i] == qt.points[:,1])
        end

        # all points are equal, stop recursion
        if allequal
            return
        end

        split!(qt)
    end

    for child in qt.children
        rsplit!(child,max_cap)
    end

end


"""
    attribs = within(qt,min,max)

Search all points within a bounding box defined by the vectors `min` and `max`.
"""

function within(qt::QT{T,TA,N}, min, max) where {T,TA,N}
    attribs = TA[]
    sizehint!(attribs,1)
    within!(qt,min,max,attribs)
    return attribs
end

function within!(qt::QT{T,TA,N}, min, max, attribs) where {T,TA,N}
    #@show Base.intersect(qt, min, max), min, max, qt.min, qt.max
    if !Base.intersect(qt, min, max)
        # nothing to do
        return
    end

    if isleaf(qt)
        #@show "checking"
        @inbounds for i = 1:length(qt)
            if inside(min,max,qt.points[:,i])
                push!(attribs,qt.attribs[i])
            end
        end
        return 
    end
        
    for child in qt.children
        within!(child, min, max, attribs)
    end
    
    return attribs    
end

function withincount!(qt::QT{T,TA,N}, min, max, count) where {T,TA,N}
    if !Base.intersect(qt, min, max)
        # nothing to do
        return
    end

    if isleaf(qt)
        #@show "checking"
        @inbounds for i = 1:length(qt)
            #if inside(min,max,qt.points[:,i])
            if inside(min,max,view(qt.points,:,i))
                count[ qt.attribs[i] ] += 1
            end
        end
        return 
    end
        
    for child in qt.children
        withincount!(child, min, max, count)
    end
end


function qplot(qt::QT)
    plot([qt.min[1], qt.max[1], qt.max[1], qt.min[1], qt.min[1]],
         [qt.min[2], qt.min[2], qt.max[2], qt.max[2], qt.min[2]])
end

function rplot(qt::QT)
    qplot(qt)
    for child in qt.children
        #@show child
        rplot(child)
    end
end

function Base.show(io::IO,qt::QT; indent = "  ")
    if isleaf(qt)
        print_with_color(:green, io, indent,"Leaf $(length(qt))")
    else
        print_with_color(:blue, io, indent,"Node ")
    end
    print(io,"  from $(qt.min) to $(qt.max)\n")

    if !isleaf(qt)
        for child in qt.children
            show(io,child; indent = indent * "  ")
        end
    end
end


# duplicates


"""
    dupl = check_duplicates(x,delta)

Based the coordinates `x` (a tuple of longitude `lons`, latitudes `lats`, depth (`zs`) 
and time (`times`)) check of points who are in the same spatio-temporal bounding
 box of a length `delta`. `delta` is a vector with 4 elements corresponding to 
longitude, latitude, depth and time
(in days). `mult` is a vector of the same length than `lons` with the number of
time an observation is present within this bounding box and `duplicates` a list
of duplicates and each element of `duplicates` corresponds to the index in
`lons`, `lats`, `zs` and times`.
"""

function check_duplicates(x,delta; maxcap = 100, label = collect(1:size(x[1],1)))
    n = length(x)
    Nobs = length(x[1])

    X = Array{Float64,2}(n,Nobs)
    for i = 1:n
        if eltype(x[i]) <: DateTime
            for j = 1:Nobs
                X[i,j] = Dates.Millisecond(x[i][j] - DateTime(1900,1,1)).value/24/60/60/1000
            end
        else
            X[i,:] = x[i]
        end
    end

    qt = Quadtrees.QTnew(X,label)
    Quadtrees.rsplit!(qt, maxcap)
    
    #mult = Vector{Int}(size(X,1))
    duplicates = Vector{Set{Int}}(0)
    delta2 = delta/2

    xmin = zeros(n)
    xmax = zeros(n)
    
    @fastmath @inbounds for i = 1:Nobs
        for j = 1:n
            xmin[j] = X[j,i] - delta2[j]
            xmax[j] = X[j,i] + delta2[j]
        end

        index = Quadtrees.within(qt,xmin,xmax)

        #@show index
        #mult = length(index)
        if length(index) > 1
            push!(duplicates,Set(index))
            #@show index
        end
    end

    #return mult,duplicates
    return collect(Set(duplicates))
end

function dupset(duplicates)
    d = Vector{Set{Int}}()
    sizehint!(d,length(duplicates) ÷ 2)
    
    for i = 1:length(duplicates)
        if !(duplicates[i] in d)
            push!(d,duplicates[i])
        end
    end

    return d
end





"""
    dupl = check_duplicates(x,delta)

Based the coordinates `x` (a tuple of longitude `lons`, latitudes `lats`, depth (`zs`) 
and time (`times`)) check of points who are in the same spatio-temporal bounding
 box of a length `delta`. `delta` is a vector with 4 elements corresponding to 
longitude, latitude, depth and time
(in days). `mult` is a vector of the same length than `lons` with the number of
time an observation is present within this bounding box and `duplicates` a list
of duplicates and each element of `duplicates` corresponds to the index in
`lons`, `lats`, `zs` and times`.
"""

function check_duplicatesv(x,value,delta,deltavalue; maxcap = 100, label = collect(1:size(x[1],1)))
    n = length(x)
    Nobs = length(x[1])

    X = Array{Float64,2}(n,Nobs)
    for i = 1:n
        if eltype(x[i]) <: DateTime
            for j = 1:Nobs
                X[i,j] = Dates.Millisecond(x[i][j] - DateTime(1900,1,1)).value/24/60/60/1000
            end
        else
            X[i,:] = x[i]
        end
    end

    qt = Quadtrees.QTnew(X,label)
    Quadtrees.rsplit!(qt, maxcap)
    
    #mult = Vector{Int}(size(X,1))
    duplicates = Vector{Set{Int}}(0)
    delta2 = delta/2

    xmin = zeros(n)
    xmax = zeros(n)
    
    @fastmath @inbounds for i = 1:Nobs
        for j = 1:n
            xmin[j] = X[j,i] - delta2[j]
            xmax[j] = X[j,i] + delta2[j]
        end

        index = Quadtrees.within(qt,xmin,xmax)

        #@show index

        if length(index) > 1
            # check for values
            vv = value[index]
            ii = sortperm(vv)
            
            istart = 1
            for i=1:length(vv)-1
                if vv[ii[i+1]] - vv[ii[i]] > deltavalue
                    #@show istart:i;

                    if i > istart
                        push!(duplicates,Set(index[ii[istart:i]]))
                    end
                    
                    istart=i+1
                end
            end
            i = length(vv)
            if i > istart
                push!(duplicates,Set(index[ii[istart:i]]))
            end
            
            #push!(duplicates,Set(index))
            #@show index
        end
    end

    #return mult,duplicates
    #return dupset(duplicates)
    return duplicates
end

function catx(x::Tuple)
    n = length(x)
    Nobs = length(x[1])

    X = Array{Float64,2}(n,Nobs)
    for i = 1:n
        if eltype(x[i]) <: DateTime
            for j = 1:Nobs
                X[i,j] = Dates.Millisecond(x[i][j] - DateTime(1900,1,1)).value/24/60/60/1000
            end
        else
            X[i,:] = x[i]
        end
    end
    return X
end


"""
    dupl = checkduplicates(x,value,delta,deltavalue)

Based the coordinates `x` (a tuple of longitude `lons`, latitudes `lats`, depth (`zs`) 
and time (`times`)) check of points who are in the same spatio-temporal bounding
 box of a length `delta`. `delta` is a vector with 4 elements corresponding to 
longitude, latitude, depth and time
(in days). `dupl` a vector of vectors containing indices of the duplicates.
"""

function checkduplicates(x::Tuple,value,delta,deltavalue;
                         maxcap = 100, label = collect(1:size(x[1],1)))
    n = length(x)
    Nobs = length(x[1])

    X = Array{Float64,2}(n,Nobs)
    for i = 1:n
        if eltype(x[i]) <: DateTime
            for j = 1:Nobs
                X[i,j] = Dates.Millisecond(x[i][j] - DateTime(1900,1,1)).value/24/60/60/1000
            end
        else
            X[i,:] = x[i]
        end
    end

    qt = Quadtrees.QTnew(X,label)
    Quadtrees.rsplit!(qt, maxcap)
    
    #mult = Vector{Int}(size(X,1))
    duplicates = Vector{Set{Int}}(0)
    delta2 = delta/2

    xmin = zeros(n)
    xmax = zeros(n)
    
    @fastmath @inbounds for i = 1:Nobs
        for j = 1:n
            xmin[j] = X[j,i] - delta2[j]
            xmax[j] = X[j,i] + delta2[j]
        end

        index = Quadtrees.within(qt,xmin,xmax)

        #@show index

        if length(index) > 1
            # check for values
            vv = value[index]
            ii = sortperm(vv)
            
            istart = 1
            for i=1:length(vv)-1
                if vv[ii[i+1]] - vv[ii[i]] > deltavalue
                    #@show istart:i;

                    if i > istart
                        push!(duplicates,Set(index[ii[istart:i]]))
                    end
                    
                    istart=i+1
                end
            end
            i = length(vv)
            if i > istart
                push!(duplicates,Set(index[ii[istart:i]]))
            end
            
            #push!(duplicates,Set(index))
            #@show index
        end
    end

    # collect(Set(...)) returns unique elements
    # collect.() transform the list of sets into a list of list
    return sort.(collect.(collect(Set(duplicates))))

end

"""
    dupl = checkduplicates(x1,value1,v2,value2,delta,deltavalue)

"""

function checkduplicates(x1::Tuple,value1,
                         x2::Tuple,value2,
                         delta, deltavalue;
                         maxcap = 100,
                         label1 = collect(1:size(x1[1],1))
                         )
    X1 = catx(x1)
    X2 = catx(x2)

    n = size(X1,1)
    Nobs1 = size(X1,2)
    Nobs2 = size(X2,2)

    qt = Quadtrees.QTnew(X1,label1)
    Quadtrees.rsplit!(qt, maxcap)
    
    duplicates = Vector{Vector{Int}}(Nobs2)
    delta2 = delta/2

    xmin = zeros(n)
    xmax = zeros(n)
    
    @fastmath @inbounds for i = 1:Nobs2
        for j = 1:n
            xmin[j] = X2[j,i] - delta2[j]
            xmax[j] = X2[j,i] + delta2[j]
        end

        index = Quadtrees.within(qt,xmin,xmax)

        if length(index) > 0            
            # check for values
            vv = value1[index]
            duplicates[i] = sort(index[abs.(vv - value2[i]) .< deltavalue])
        else
            duplicates[i] = Int[]
        end
    end

    return duplicates
end


export  QT, rsplit!, add!, show, ndims, count
    
end # module
