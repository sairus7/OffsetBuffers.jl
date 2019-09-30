"""
    RollingBuffer{T}(n)
The RollingBuffer type implements a circular buffer of fixed capacity,
similar to CircularBuffer from DataStructures.jl, but with growing indexes.

New items are pushed to the back of the list, overwriting values
in a circular fashion, and increasing starting index by one.

Allocate a buffer of elements of type `T` with maximum capacity `n`.
"""
mutable struct RollingBuffer{T} <: AbstractVector{T}
    buffer::Vector{T}
    capacity::Int
    length::Int
    offset::Int # change to delta for faster _buffer_index? delta = buf.offset + buf.first - 1
    first::Int
    last::Int
    final::Int # !specific - number of elements that are already processed in some sense
end

function RollingBuffer{T}(maxlen::Int, offset::Int = 0) where T
    RollingBuffer{T}(Vector{T}(undef, maxlen), maxlen, 0, offset, 1, 0, -1)
end

RollingBuffer(capacity) = RollingBuffer{Any}(capacity)

function RollingBuffer(vec::Vector{T}, offset::Int = 0) where T
    capacity = length(vec)
    RollingBuffer{T}(vec, capacity, capacity, offset, 1, capacity, -1)
end

# no copy for native vector type
RollingBuffer(v::Vector{T}, inds::AbstractUnitRange) where {T} =
    RollingBuffer(v, first(inds)-1)

RollingBuffer(v::AbstractVector{T}, inds::AbstractUnitRange) where {T} =
    RollingBuffer(collect(v), first(inds)-1)

RollingBuffer(v::AbstractVector) = RollingBuffer(v, Base.axes1(v))

Base.@propagate_inbounds function _buffer_index_checked(buf::RollingBuffer, i::Int)
    @boundscheck if i < firstindex(buf) || i > lastindex(buf)
        throw(BoundsError(buf, i))
    end
    _buffer_index(buf, i)
end

@inline function _buffer_index(buf::RollingBuffer, i::Int)
    idx = i - buf.offset + buf.first - 1     # idx = mod1(buf.first + i - 1, buf.capacity) # idx = (buf.first + i - 2) % buf.capacity + 1
    if idx > buf.capacity
        idx -= buf.capacity
    end
    idx #idx = buf.first + i - 1 #idx > buf.capacity ? idx - buf.capacity : idx
end

@inline Base.@propagate_inbounds function Base.getindex(buf::RollingBuffer, i::Int)
    buf.buffer[_buffer_index_checked(buf, i)]
end

@inline Base.@propagate_inbounds function Base.setindex!(buf::RollingBuffer, data, i::Int)
    buf.buffer[_buffer_index_checked(buf, i)] = data
    buf
end

# pop_back
@inline function Base.pop!(buf::RollingBuffer)
    i = buf.last
    if buf.length > 0
        buf.length -= 1
        buf.last = (buf.last <= 1 ? buf.capacity : buf.last - 1)
    else
        throw(ArgumentError("array must be non-empty"))
    end
    buf.buffer[i]
end
@inline function Base.pop!(buf::RollingBuffer, Npop::Integer)
    if Npop > buf.length
        Npop = buf.length
    end
    if buf.length > 0
        buf.length -= Npop
        buf.last = (buf.last > Npop ? buf.last - Npop : buf.last - Npop + buf.capacity)
    end
    buf
end

# pop_front
function Base.popfirst!(buf::RollingBuffer)
    i = buf.first
    if buf.length > 0
        buf.length -= 1
        buf.first = (buf.first == buf.capacity ? 1 : buf.first + 1)
        buf.offset += 1
    else
        throw(ArgumentError("array must be non-empty"))
    end
    buf.buffer[i]
end
function Base.popfirst!(buf::RollingBuffer, Npop::Integer)
    if Npop > buf.length
        Npop = buf.length
    end
    if buf.length > 0
        buf.length -= Npop
        buf.first += Npop
        buf.first = (buf.first > buf.capacity ? buf.first - buf.capacity : buf.first)
        buf.offset += Npop
    end
    buf
end

# push_back
@inline function Base.push!(buf::RollingBuffer, data)
    if buf.length == buf.capacity # increase offset and first point, if full
        buf.first = (buf.first == buf.capacity ? 1 : buf.first + 1)
        buf.offset += 1
    else # increase capacity, if not full
        buf.length += 1
    end
    buf.last = (buf.last == buf.capacity ? 1 : buf.last + 1)
    buf.buffer[buf.last] = data
    buf
end

# push_front - additional function
function Base.pushfirst!(buf::RollingBuffer, data)
    if buf.length == buf.capacity
        buf.last = (buf.last <= 1 ? buf.capacity : buf.last - 1)
    else
        buf.length += 1
    end
    buf.offset -= 1
    buf.first = (buf.first <= 1 ? buf.capacity : buf.first - 1)
    buf.buffer[buf.first] = data
    buf
end

# push_back vector
@inline Base.push!(buf::RollingBuffer, datavec::AbstractVector) = Base.append!(buf::RollingBuffer, datavec::AbstractVector)

@inbounds function Base.append!(buf::RollingBuffer, datavec::AbstractVector)
    Nadd = length(datavec)
    Nadd > buf.capacity && error("Added length larger than buffer length!")

    lenRight = buf.capacity - buf.last
    bshift = buf.last # dst = pointer(buf.buffer, buf.last + 1)
    shift = 0 #src = pointer(datavec, 1)
    if lenRight < Nadd # there is not enough space at the end of the buffer
        copyto!(buf.buffer, bshift+1, datavec, shift+1, lenRight) # unsafe_copyto!(dst, src, lenRight)
        buf.last = Nadd - lenRight
        bshift = 0 #dst = pointer(buf.buffer, 1)
        shift = lenRight #src = pointer(datavec, lenRight + 1)
        copyto!(buf.buffer, bshift+1, datavec, shift+1, buf.last) #unsafe_copyto!(dst, src, buf.last)
    else # buf.last < buf.capacity
        copyto!(buf.buffer, bshift+1, datavec, shift+1, Nadd) # unsafe_copyto!(dst, src, Nadd)
        buf.last += Nadd
    end

    if buf.length == buf.capacity # most frequent case = buffer is full
        buf.first += Nadd #_buffer_index(buf, buf.first + Nadd)
        buf.first = (buf.first > buf.capacity ? buf.first - buf.capacity : buf.first)
        buf.offset += Nadd
    else
        if buf.capacity < buf.length + Nadd
            Nadd -= buf.capacity - buf.length
            buf.first += Nadd
            buf.first = (buf.first > buf.capacity ? buf.first - buf.capacity : buf.first)
            buf.offset += Nadd
            buf.length = buf.capacity;
        else
            buf.length += Nadd;
        end
    end
    buf
end

# Preparing a place for the next append of a fixed size without actual append.
# One should assign `buf[nextindex:end]` after this call!
@inbounds function prepare_append!(buf::RollingBuffer, Nadd::Int)
    Nadd > buf.capacity && error("Added length larger than buffer length!")
    nextindex = buf.offset + buf.length + 1
    lenRight = buf.capacity - buf.last
    if lenRight < Nadd # there is not enough space at the end of the buffer
        buf.last = Nadd - lenRight
    else # buf.last < buf.capacity
        buf.last += Nadd
    end
    if buf.length == buf.capacity # most frequent case = buffer is full
        buf.first += Nadd #_buffer_index(buf, buf.first + Nadd)
        buf.first = (buf.first > buf.capacity ? buf.first - buf.capacity : buf.first)
        buf.offset += Nadd
    else
        if buf.capacity < buf.length + Nadd
            Nadd -= buf.capacity - buf.length
            buf.first += Nadd
            buf.first = (buf.first > buf.capacity ? buf.first - buf.capacity : buf.first)
            buf.offset += Nadd
            buf.length = buf.capacity;
        else
            buf.length += Nadd;
        end
    end
    nextindex
end

function Base.empty!(buf::RollingBuffer)
    buf.first = 1
    buf.last = buf.length = buf.offset = 0
    buf
end

function Base.fill!(cb::RollingBuffer, data)
    for i in 1:capacity(cb)-length(cb)
        push!(cb, data)
    end
    cb
end

Base.parent(A::RollingBuffer) = A.buffer

Base.@propagate_inbounds function Base.first(buf::RollingBuffer)
    @boundscheck if buf.length == 0
        throw(BoundsError(buf, 1))
    end
    buf.buffer[buf.first]
end
Base.@propagate_inbounds function Base.last(buf::RollingBuffer)
    @boundscheck if buf.length == 0
        throw(BoundsError(buf, 1))
    end
    buf.buffer[buf.last]
end


Base.length(buf::RollingBuffer) = buf.length
Base.size(buf::RollingBuffer) = (length(buf),)
Base.isempty(buf::RollingBuffer) = buf.length == 0
#Base.convert(::Type{Array}, buf::RollingBuffer{T}) where T = T[x for x in buf]
# convert buffer to a 1-based indexed array, dropping its offset
function Base.convert(::Type{Array}, buf::RollingBuffer{T}) where {T}
    len = length(buf)
    vec = Vector{T}(undef, len)
    for (i, j) in zip(1:len, eachindex(buf))
        @inbounds vec[i] = buf[j]
    end
    vec
end
# copy buffer to another array, dropping its offset
function Base.copyto!(dest::Vector, src::RollingBuffer)
    if length(dest) != length(src)
        if length(dest) < length(src)
            throw(BoundsError(dest, length(src)))
        else
            throw(BoundsError(src, firstindex(src)-1+length(dest)))
        end
    end

    for (i, j) in zip(eachindex(dest), eachindex(src))
        @inbounds dest[i] = src[j]
    end
    dest
end


Base.lastindex(buf::RollingBuffer) = buf.offset + buf.length #count
Base.firstindex(buf::RollingBuffer) = buf.offset + 1 #countfirst

# if final is not used, it is equal to the last element
finalindex(buf::RollingBuffer) = buf.final < 0 ? lastindex(buf) : buf.final # !specific
setfinalindex(buf::RollingBuffer, i::Int) = buf.final = i # !specific
addfinalindex(buf::RollingBuffer, i::Int) = buf.final = (buf.final < 0) ? i : buf.final + i # !specific
final(buf::RollingBuffer) = buf[finalindex(buf)]

# specific
offset(buf::RollingBuffer) = buf.offset
capacity(buf::RollingBuffer) = buf.capacity # maximum available length
isfull(buf::RollingBuffer) = buf.length == buf.capacity
#eachindex bounds(buf::RollingBuffer) = (buf.first, buf.last) # bound indexes

# clear and resize
function reset!(buf::RollingBuffer, capacity::Int = buf.capacity, offset::Int = 0) # clear and resize
    empty!(buf)
    buf.offset = offset
    if buf.capacity != capacity
        buf.capacity = capacity
        buf.buffer = Vector{T}(undef, capacity)
    end
end

# custom indexing
# @inline Base.axes(A::RollingBuffer) =  (_slice(A.offset + 1, A.length),)
#@inline _slice(start, capacity) = Base.IdentityUnitRange(Base._range(start, nothing, nothing, capacity))
Base.axes1(buf::RollingBuffer) = URange(1 + buf.offset, buf.length + buf.offset)
Base.axes(buf::RollingBuffer) = (Base.axes1(buf),)

function Base.similar(v::RollingBuffer, T::Type, inds::Tuple{URange})
    inds1 = inds[1]
    n = length(inds1)
    RollingBuffer(Array{T}(undef, n), first(inds1)-1)
end

function Base.similar(f::Union{Function,Type}, inds::Tuple{URange})
    inds1 = inds[1]
    n = length(inds1)
    RollingBuffer(f(Base.OneTo(n)), first(inds1)-1)
end

#=
function Base.similar(::Type{T}, inds::Tuple{URange}) where {T<:AbstractArray}
    inds1 = inds[1]
    n = length(inds1)
    RollingBuffer(Array{T}(undef, n), first(inds1)-1)
end
=#
