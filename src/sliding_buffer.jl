"""
    SlidingBuffer{T}(n)
The SlidingBuffer type implements a linear buffer of fixed capacity,
similar to CircularBuffer from DataStructures.jl, but with growing indexes
and storing its data linearly as a contiguous block of memory from old to new.

New items are pushed to the back of the list, overwriting values
in a circular fashion, and increasing starting index by one.

When there is not enough space at the end, old items are copied to the front of
the internal array of `fullLen` length. `capacity <= fullLen` ensures that memmove
is performed at every `fulLen-capacity+1` added items.

Allocate a buffer of elements of type `T` with maximum capacity `n`.
"""
mutable struct SlidingBuffer{T} <: AbstractVector{T}
    buffer::Vector{T}
    fullLen::Int
    capacity::Int
    length::Int
    offset::Int # change to delta for faster _buffer_index? delta = buf.offset + buf.first - 1
    first::Int
    last::Int
    final::Int # !specific - number of elements that are already processed in some sense
end

function SlidingBuffer{T}(capacity::Int, fullLen::Int = capacity, offset::Int = 0) where T
    SlidingBuffer{T}(Vector{T}(undef, fullLen), fullLen, capacity, 0, offset, 1, 0, -1)
end

SlidingBuffer(capacity) = SlidingBuffer{Any}(capacity)

SlidingBuffer(v::Vector{T}, offset::Int) where {T} =
    SlidingBuffer(v, length(v), length(v), length(v), offset, 1, length(v), -1)

# no copy for native vector type
SlidingBuffer(v::Vector{T}, inds::AbstractUnitRange) where {T} =
    SlidingBuffer(v, first(inds)-1)

SlidingBuffer(v::AbstractVector{T}, inds::AbstractUnitRange) where {T} =
    SlidingBuffer(collect(v), first(inds)-1)

SlidingBuffer(v::AbstractVector) = SlidingBuffer(v, Base.axes1(v))

Base.@propagate_inbounds function _buffer_index_checked(buf::SlidingBuffer, i::Int)
    @boundscheck if i < firstindex(buf) || i > lastindex(buf)
        throw(BoundsError(buf, i))
    end
    _buffer_index(buf, i)
end

@inline function _buffer_index(buf::SlidingBuffer, i::Int)
    idx = i - buf.offset + buf.first - 1
end

@inline Base.@propagate_inbounds function Base.getindex(buf::SlidingBuffer, i::Int)
    buf.buffer[_buffer_index_checked(buf, i)]
end

@inline Base.@propagate_inbounds function Base.setindex!(buf::SlidingBuffer, data, i::Int)
    buf.buffer[_buffer_index_checked(buf, i)] = data
    buf
end

# pop_back one element and return it
@inline function Base.pop!(buf::SlidingBuffer)
    i = buf.last
    if buf.length > 0
        buf.length -= 1
        buf.last -= 1
    else
        throw(ArgumentError("array must be non-empty"))
    end
    buf.buffer[i]
end
@inline function Base.pop!(buf::SlidingBuffer, Npop::Integer)
    if Npop > buf.length
        Npop = buf.length
    end
    if buf.length > 0
        buf.length -= Npop
        buf.last -= Npop
    end
    buf
end

# pop_front
function Base.popfirst!(buf::SlidingBuffer)
    i = buf.first
    if buf.length > 0
        buf.length -= 1
        buf.first += 1
        buf.offset += 1
    else
        throw(ArgumentError("array must be non-empty"))
    end
    buf.buffer[i]
end
function Base.popfirst!(buf::SlidingBuffer, Npop::Integer)
    if Npop > buf.length
        Npop = buf.length
    end
    if buf.length > 0
        buf.length -= Npop
        buf.first += Npop
        buf.offset += Npop
    end
    buf
end

# push_back one element
@inline function Base.push!(buf::SlidingBuffer, data)
    if buf.length == buf.capacity # increase offset and first point, if full
        buf.first += 1
        buf.offset += 1
    else # increase capacity, if not full
        buf.length += 1
    end
    if buf.last == buf.fullLen # shift data to the front
        copylen = buf.length - 1
        # dst = pointer(buf.buffer, 1)
        # src = pointer(buf.buffer, buf.fullLen - copylen + 1)
        # unsafe_copyto!(dst, src, copylen)
        idst = 1
        isrc = buf.fullLen - copylen + 1
        copyto!(buf.buffer, idst, buf.buffer, isrc, copylen)

        buf.first = 1
        buf.last = buf.length
    else
        buf.last += 1
    end
    buf.buffer[buf.last] = data
    buf
end
# push_front one element
@inline function Base.pushfirst!(buf::SlidingBuffer, data)
    if buf.length == buf.capacity # increase offset and first point, if full
        buf.last -= 1 # buf.first += 1
        # buf.offset += 1
    else # increase capacity, if not full
        buf.length += 1
    end
    buf.offset -= 1
    if buf.first == 1 # shift data to the end
        copylen = buf.length - 1
        idst = 2
        isrc = 1
        copyto!(buf.buffer, idst, buf.buffer, isrc, copylen)

        buf.first = 1
        buf.last = buf.length
    else
        buf.first -= 1
    end
    buf.buffer[buf.first] = data
    buf
end
# not available

# push_back vector
@inline Base.push!(buf::SlidingBuffer, datavec::AbstractVector) = Base.append!(buf::SlidingBuffer, datavec::AbstractVector)

function Base.append!(buf::SlidingBuffer, datavec::AbstractVector)
    Nadd = length(datavec)
    Nadd > buf.capacity && error("Added length larger than buffer length!")

    Nold = min(buf.length, buf.capacity - Nadd) # old data that remains in buffer after add
    buf.offset += buf.length - Nold # change first point offset
    if buf.last + Nadd > buf.fullLen # there is not enough space at the end of the buffer
        if Nold > 0 # shift old data to the front
            bshift = 1 #dst = pointer(buf.buffer, 1)
            shift = buf.last - Nold + 1 #src = pointer(buf.buffer, buf.last - Nold + 1)
            copyto!(buf.buffer, bshift, buf.buffer, shift, Nold) #unsafe_copyto!(dst, src, Nold)
        end
        bshift = Nold + 1 # dst = pointer(buf.buffer, Nold + 1)
        buf.first = 1
        buf.last = Nold + Nadd
        buf.length = buf.last
    else
        bshift = buf.last + 1 # dst = pointer(buf.buffer, buf.last + 1)
        buf.first = buf.last - Nold + 1
        buf.last += Nadd
        buf.length = Nold + Nadd
    end
    shift = 1 #src = pointer(datavec, 1)
    copyto!(buf.buffer, bshift, datavec, shift, Nadd) #unsafe_copyto!(dst, src, Nadd)
    buf
end

# Preparing a place for the next append of a fixed size without actual append.
# One should assign `buf[nextindex:end]` after this call!
function prepare_append!(buf::SlidingBuffer, Nadd::Int)
    Nadd > buf.capacity && error("Added length larger than buffer length!")
    nextindex = buf.offset + buf.length + 1
    Nold = min(buf.length, buf.capacity - Nadd) # old data that remains in buffer after add
    buf.offset += buf.length - Nold # change first point offset
    if buf.last + Nadd > buf.fullLen # there is not enough space at the end of the buffer
        if Nold > 0 # shift old data to the front
            bshift = 1 #dst = pointer(buf.buffer, 1)
            shift = buf.last - Nold + 1 #src = pointer(buf.buffer, buf.last - Nold + 1)
            copyto!(buf.buffer, bshift, buf.buffer, shift, Nold) #unsafe_copyto!(dst, src, Nold)
        end
        buf.first = 1
        buf.last = Nold + Nadd
        buf.length = buf.last
    else
        buf.first = buf.last - Nold + 1
        buf.last += Nadd
        buf.length = Nold + Nadd
    end
    nextindex
end

function Base.empty!(buf::SlidingBuffer)
    buf.first = 1
    buf.last = buf.length = buf.offset = 0
    buf
end

function Base.fill!(cb::SlidingBuffer, data)
    for i in 1:capacity(cb)-length(cb)
        push!(cb, data)
    end
    cb
end

Base.parent(A::SlidingBuffer) = A.buffer

Base.@propagate_inbounds function Base.first(buf::SlidingBuffer)
    @boundscheck if buf.length == 0
        throw(BoundsError(buf, 1))
    end
    buf.buffer[buf.first]
end
Base.@propagate_inbounds function Base.last(buf::SlidingBuffer)
    @boundscheck if buf.length == 0
        throw(BoundsError(buf, 1))
    end
    buf.buffer[buf.last]
end


Base.length(buf::SlidingBuffer) = buf.length
Base.size(buf::SlidingBuffer) = (length(buf),)
Base.isempty(buf::SlidingBuffer) = buf.length == 0
#Base.convert(::Type{Array}, buf::RollingBuffer{T}) where T = T[x for x in buf]
# convert buffer to a 1-based indexed array, dropping its offset
function Base.convert(::Type{Array}, buf::SlidingBuffer{T}) where {T}
    len = length(buf)
    vec = Vector{T}(undef, len)
    for (i, j) in zip(1:len, eachindex(buf))
        @inbounds vec[i] = buf[j]
    end
    vec
end
# copy buffer to another array, dropping its offset
function Base.copyto!(dest::Vector, src::SlidingBuffer)
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

Base.lastindex(buf::SlidingBuffer) = buf.offset + buf.length #count
Base.firstindex(buf::SlidingBuffer) = buf.offset + 1 #countfirst

# if final is not used, it is equal to the last element
finalindex(buf::SlidingBuffer) = buf.final < 0 ? lastindex(buf) : buf.final # !specific
setfinalindex(buf::SlidingBuffer, i::Int) = buf.final = i # !specific
addfinalindex(buf::SlidingBuffer, i::Int) = buf.final = (buf.final < 0) ? i : buf.final + i # !specific
final(buf::SlidingBuffer) = buf[finalindex(buf)]


# specific
offset(buf::SlidingBuffer) = buf.offset
capacity(buf::SlidingBuffer) = buf.capacity # maxinum available length
isfull(buf::SlidingBuffer) = buf.length == buf.capacity
#eachindex bounds(buf::SlidingBuffer) = (buf.first, buf.last) # индексы границ

# clear and resize
function reset!(buf::SlidingBuffer, capacity::Int = buf.capacity, fullLen::Int = buf.fullLen, offset::Int = 0)
    empty!(buf)
    buf.offset = offset
    buf.capacity = capacity
    if buf.fullLen != fullLen
        buf.fullLen = fullLen
        buf.buffer = Vector{T}(undef, fullLen)
    end
end

# custom indexing
# @inline Base.axes(A::SlidingBuffer) =  (_slice(A.offset + 1, A.length),)
#@inline _slice(start, capacity) = Base.IdentityUnitRange(Base._range(start, nothing, nothing, capacity))
Base.axes1(buf::SlidingBuffer) = URange(1 + buf.offset, buf.length + buf.offset)
Base.axes(buf::SlidingBuffer) = (Base.axes1(buf),)

function Base.similar(v::SlidingBuffer, T::Type, inds::Tuple{URange})
    inds1 = inds[1]
    n = length(inds1)
    SlidingBuffer(Array{T}(undef, n), first(inds1)-1)
end


#= Rolling buffer has higher priority over this
function Base.similar(f::Union{Function,Type}, inds::Tuple{URange})
    inds1 = inds[1]
    n = length(inds1)
    SlidingBuffer(f(Base.OneTo(n)), first(inds1)-1)
end
=#

#=
function Base.similar(::Type{T}, inds::Tuple{URange}) # where {T<:SlidingBuffer}
    inds1 = inds[1]
    n = length(inds1)
    SlidingBuffer(f(Base.OneTo(n)), first(inds1)-1)
end
=#
